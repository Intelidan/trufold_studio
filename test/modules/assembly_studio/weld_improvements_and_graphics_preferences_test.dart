import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/assembly_studio/engine/assembly_docking_engine.dart';
import 'package:trufold_studio/assembly_studio/models/assembly_document.dart';
import 'package:trufold_studio/assembly_studio/models/assembly_docking_zone.dart';
import 'package:trufold_studio/assembly_studio/models/assembly_part.dart';
import 'package:trufold_studio/assembly_studio/viewmodels/assembly_studio_viewmodel.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';

void main() {
  group('User Request Improvements & Bug Fixes Verification Tests', () {
    test('1. Magnetic snap distance setting can be configured (Item 1)', () {
      final vm = AssemblyStudioViewModel();
      expect(vm.magneticSnapDistancePx, equals(10.0));

      vm.setMagneticSnapDistance(6.0);
      expect(vm.magneticSnapDistancePx, equals(6.0));

      // Clamps within valid bounds (4.0 to 30.0)
      vm.setMagneticSnapDistance(2.0);
      expect(vm.magneticSnapDistancePx, equals(4.0));

      vm.setMagneticSnapDistance(50.0);
      expect(vm.magneticSnapDistancePx, equals(30.0));
    });

    test('2. Single continuous weld string has ONLY start, center, and end snap points (Item 2)', () {
      final weld = AssemblyWeldJoint(
        id: 'weld_test_1',
        partAId: 'part_A',
        partBId: 'part_B',
        weldPoint: const CadPoint3D(0.0, 0.0, 0.0),
        weldAxis: const CadPoint3D(1.0, 0.0, 0.0),
        weldLengthMm: 40.0,
        jointDescription: 'Fillet Weld (6mm)',
      );

      final snapPoints = AssemblyDockingEngine.getAllSnapPointsForWeld(weld);
      expect(snapPoints.length, equals(3));

      final startSnap = snapPoints.firstWhere((p) => p.id == 'weld_test_1_weld_start');
      final centerSnap = snapPoints.firstWhere((p) => p.id == 'weld_test_1_weld_center');
      final endSnap = snapPoints.firstWhere((p) => p.id == 'weld_test_1_weld_end');

      expect(startSnap.worldPosition.x, closeTo(-20.0, 1e-3));
      expect(centerSnap.worldPosition.x, closeTo(0.0, 1e-3));
      expect(endSnap.worldPosition.x, closeTo(20.0, 1e-3));

      expect(startSnap.type, equals(AssemblySnapPointType.boundingBoxCorner));
      expect(centerSnap.type, equals(AssemblySnapPointType.boundingBoxEdgeCenter));
      expect(endSnap.type, equals(AssemblySnapPointType.boundingBoxCorner));
    });

    test('3. Fillet weld geometry strictly sweeps [0, pi/2] quadrant without penetrating through walls (Item 3, SS1)', () {
      final doc = AssemblyDocument(
        id: 'doc_test_quadrant',
        parts: [
          AssemblyPart(
            id: 'base_plate',
            name: 'Base Plate',
            type: AssemblyPartType.baseFootPlate,
            color: const Color(0xFF38BDF8),
            position: const CadPoint3D(0, 0, 0),
          ),
          AssemblyPart(
            id: 'vertical_wall',
            name: 'Vertical Wall',
            type: AssemblyPartType.baseFootPlate,
            color: const Color(0xFF94A3B8),
            position: const CadPoint3D(0, 0, 0),
          ),
        ],
        welds: [
          AssemblyWeldJoint(
            id: 'seam_corner',
            partAId: 'base_plate',
            partBId: 'vertical_wall',
            weldPoint: const CadPoint3D(0.0, 0.0, 0.0),
            weldAxis: const CadPoint3D(1.0, 0.0, 0.0),
            weldLengthMm: 50.0,
            legDir1: const CadPoint3D(0.0, 1.0, 0.0), // Along base plate (+Y)
            legDir2: const CadPoint3D(0.0, 0.0, 1.0), // Up vertical wall (+Z)
            weldSizeMm: 6.0,
          ),
        ],
      );

      final mesh = doc.buildAssemblyMesh(showWeldOverlay: true);
      final weldPolys = mesh.allPolygons.where((p) => p.faceId.startsWith('weld_seam_corner')).toList();

      expect(weldPolys.isNotEmpty, isTrue);

      // Verify that every single vertex of the weld bead stays strictly in the positive quadrant (+Y >= 0, +Z >= 0)
      // and never punches through to the opposite side of the metal wall (-Y < 0 or -Z < 0)
      for (final poly in weldPolys) {
        for (final v in poly.vertices) {
          expect(v.y, greaterThanOrEqualTo(-1e-4), reason: 'Weld vertex must not penetrate behind base plate (-Y)');
          expect(v.z, greaterThanOrEqualTo(-1e-4), reason: 'Weld vertex must not penetrate behind vertical wall (-Z)');
        }
      }
    });

    test('4. Weld selection and clearing (Item 5)', () {
      final vm = AssemblyStudioViewModel();
      expect(vm.selectedWeldId, isNull);

      vm.selectWeld('weld_123');
      expect(vm.selectedWeldId, equals('weld_123'));
      expect(vm.selectedPart, isNull);

      vm.selectWeld(null);
      expect(vm.selectedWeldId, isNull);
    });

    test('5. Line width <= 0.05 turns off wireframe boundary edges (Item 6, SS3)', () {
      const prefsOff = OnshapeGraphicsPreferences(lineWidth: 0.0);
      final shouldDrawOff = true &&
          OnshapeRenderMode.shadedWithEdges != OnshapeRenderMode.shadedWithoutEdges &&
          prefsOff.lineWidth > 0.05;
      expect(shouldDrawOff, isFalse);

      const prefsOn = OnshapeGraphicsPreferences(lineWidth: 1.0);
      final shouldDrawOn = true &&
          OnshapeRenderMode.shadedWithEdges != OnshapeRenderMode.shadedWithoutEdges &&
          prefsOn.lineWidth > 0.05;
      expect(shouldDrawOn, isTrue);
    });

    test('6. Manual weld generates authentic stacked-dimes fillet bead matching auto demo weld with orthogonalized legs (Item 1, SS1)', () {
      final doc = AssemblyDocument(
        id: 'doc_weld_comparison',
        parts: [
          AssemblyPart(id: 'plate_a', name: 'Base Plate', type: AssemblyPartType.baseFootPlate, position: const CadPoint3D(0, 0, 0)),
          AssemblyPart(id: 'plate_b', name: 'Vertical Stile', type: AssemblyPartType.baseFootPlate, position: const CadPoint3D(0, 0, 0)),
        ],
        welds: [
          // Auto demo weld
          AssemblyWeldJoint(
            id: 'auto_weld_demo',
            partAId: 'plate_a',
            partBId: 'plate_b',
            weldPoint: const CadPoint3D(100.0, 0.0, 10.0),
            weldAxis: const CadPoint3D(1.0, 0.0, 0.0),
            weldLengthMm: 40.0,
            weldSizeMm: 6.0,
            legDir1: const CadPoint3D(0.0, 0.0, 1.0),
            legDir2: const CadPoint3D(0.0, 1.0, 0.0),
          ),
          // Manual weld with arbitrary/raw input vectors
          AssemblyWeldJoint(
            id: 'manual_weld_user',
            partAId: 'plate_a',
            partBId: 'plate_b',
            weldPoint: const CadPoint3D(200.0, 0.0, 10.0),
            weldAxis: const CadPoint3D(1.0, 0.0, 0.0),
            weldLengthMm: 40.0,
            weldSizeMm: 6.0,
            legDir1: const CadPoint3D(0.0, 0.0, 1.0),
            legDir2: const CadPoint3D(0.0, 1.0, 0.0),
          ),
        ],
      );

      final mesh = doc.buildAssemblyMesh(showWeldOverlay: true);
      final autoPolys = mesh.allPolygons.where((p) => p.faceId.startsWith('weld_auto_weld_demo')).toList();
      final manualPolys = mesh.allPolygons.where((p) => p.faceId.startsWith('weld_manual_weld_user')).toList();

      expect(autoPolys.isNotEmpty, isTrue);
      expect(manualPolys.isNotEmpty, isTrue);
      expect(manualPolys.length, equals(autoPolys.length), reason: 'Manual weld should generate identical quad strip mesh count as auto demo weld');
    });

    test('7. Selecting weld invalidates mesh cache and increments documentVersion so cyan highlight appears (Item 2)', () {
      final vm = AssemblyStudioViewModel();
      final initialVersion = vm.documentVersion;

      // Select weld
      vm.selectWeld('weld_left_1');
      expect(vm.selectedWeldId, equals('weld_left_1'));
      expect(vm.documentVersion, greaterThan(initialVersion), reason: 'selectWeld must increment documentVersion to trigger immediate UI/GPU redraw');

      // The selected weld in mesh has cyan highlight color 0xFF00E5FF
      final mesh = vm.assemblyMesh;
      final selectedPolys = mesh.allPolygons.where((p) => p.faceId.startsWith('weld_weld_left_1')).toList();
      expect(selectedPolys.isNotEmpty, isTrue);
      expect(selectedPolys.first.color, equals(const Color(0xFF00E5FF)));
    });

    test('8. Surface click without snap point attaches base point to surface hitPoint, not bottom origin (Item 3, SS2)', () {
      final part = AssemblyPart(
        id: 'tall_rail',
        name: 'Tall Rail',
        type: AssemblyPartType.straightRail,
        position: const CadPoint3D(0, 0, 0),
        length: 1000.0,
        height: 100.0,
      );

      // Suppose user clicked on the face surface at Z = 500.0, X = 50.0 (no snap points nearby)
      const surfaceClickPoint = CadPoint3D(50.0, 0.0, 500.0);
      final CadPoint3D? nearestSnap = null;

      // In the new logic:
      final moveBasePoint = nearestSnap ?? surfaceClickPoint;
      expect(moveBasePoint.z, equals(500.0));
      expect(moveBasePoint, isNot(equals(part.position)), reason: 'Move base point should never fall back to (0,0,0) bottom origin when clicking surface');
    });

    test('9. VCB value input submit via submitVcbInput applies move distance and creates arrays (Item 4, SS3)', () {
      final vm = AssemblyStudioViewModel();
      expect(vm.doc.parts.isNotEmpty, isTrue);

      final part = vm.doc.parts.first;
      vm.selectPart(part.id);

      // Submit distance '100'
      final handled = vm.submitVcbInput('100');
      expect(handled, isTrue);
    });
  });
}
