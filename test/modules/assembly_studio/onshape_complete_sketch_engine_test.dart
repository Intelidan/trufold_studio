import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm_math;

import 'package:trufold_studio/assembly_studio/engine/sketch/assembly_surface_sketch_engine.dart';
import 'package:trufold_studio/assembly_studio/engine/sketch/onshape_sketch_modify_engine.dart';
import 'package:trufold_studio/assembly_studio/models/onshape_toolbar_items.dart';
import 'package:trufold_studio/assembly_studio/viewmodels/assembly_studio_viewmodel.dart';

void main() {
  group('Onshape Complete Sketch Engine & Primitives Tests', () {
    test('All 43 sketch tools are implemented (isImplemented: true)', () {
      int totalTools = 0;
      for (final group in onshapeSketchGroups) {
        for (final item in group.items) {
          totalTools++;
          expect(item.isImplemented, isTrue, reason: 'Tool ${item.id} in group ${group.id} should be implemented');
        }
      }
      expect(totalTools, greaterThanOrEqualTo(43));
    });

    test('CADMidpointLineEntity computes midpoint and endpoints correctly', () {
      final line = CADMidpointLineEntity(
        id: 'mid_line_1',
        midpoint: const Offset(10, 10),
        endpoint: const Offset(30, 20),
      );

      expect(line.end, const Offset(30, 20));
      expect(line.start, const Offset(-10, 0)); // 2*10 - 30 = -10, 2*10 - 20 = 0
      expect(line.midpoint, const Offset(10, 10));
    });

    test('CADAlignedRectangleEntity generates 4 boundary segments', () {
      final rect = CADAlignedRectangleEntity(
        id: 'aligned_rect_1',
        corner1: const Offset(0, 0),
        corner2: const Offset(40, 0),
        height: 30.0,
      );

      final segs = rect.toLineSegments();
      expect(segs.length, 4);
      expect(rect.width, closeTo(40.0, 1e-4));
      expect(rect.height, closeTo(30.0, 1e-4));
    });

    test('CADThreePointCircleEntity accurately determines circumcircle center and radius', () {
      // 3 points on a circle of radius 25 centered at (0, 0)
      final p1 = const Offset(25, 0);
      final p2 = const Offset(0, 25);
      final p3 = const Offset(-25, 0);

      final circle = CADThreePointCircleEntity(
        id: 'circle_3pt_1',
        p1: p1,
        p2: p2,
        p3: p3,
      );

      expect(circle.center.dx, closeTo(0.0, 1e-3));
      expect(circle.center.dy, closeTo(0.0, 1e-3));
      expect(circle.radius, closeTo(25.0, 1e-3));
    });

    test('CADRegularPolygonEntity creates polygon with specified sides and radius', () {
      final poly = CADRegularPolygonEntity(
        id: 'hex_1',
        center: const Offset(50, 50),
        radius: 20.0,
        sides: 6,
      );

      expect(poly.sides, 6);
      expect(poly.radius, closeTo(20.0, 1e-3));
      final segs = poly.toLineSegments();
      expect(segs.length, 6);
    });

    test('CADSlotEntity generates linear sides and semicircle arc caps', () {
      final slot = CADSlotEntity(
        id: 'slot_1',
        startCenter: const Offset(10, 10),
        endCenter: const Offset(50, 10),
        diameter: 20.0,
      );

      final segs = slot.toLineSegments();
      expect(segs.isNotEmpty, isTrue);
      expect(slot.radius, closeTo(10.0, 1e-4));
      expect(slot.diameter, closeTo(20.0, 1e-4));
    });

    test('CADPointEntity stores 2D coordinates on sketch plane', () {
      final pt = CADPointEntity(id: 'pt_1', position: const Offset(15, 25));
      expect(pt.position, const Offset(15, 25));
      expect(pt.toLineSegments(), isEmpty);
    });
  });

  group('Onshape Sketch Modify Engine Tests', () {
    test('Trim tool (M) splits intersecting lines and deletes the clicked sub-segment', () {
      final plane = CADSketchPlane(
        id: 'plane_trim',
        name: 'Trim Plane',
        origin: vm_math.Vector3.zero(),
        normal: vm_math.Vector3(0, 0, 1),
        up: vm_math.Vector3(0, 1, 0),
      );

      // Line 1: (0, 10) to (40, 10)
      final l1 = CADLineEntity(id: 'l1', start: const Offset(0, 10), end: const Offset(40, 10));
      // Line 2: (20, 0) to (20, 40)
      final l2 = CADLineEntity(id: 'l2', start: const Offset(20, 0), end: const Offset(20, 40));
      plane.primitives.addAll([l1, l2]);

      // Click at (30, 10) on the right branch of Line 1
      final trimmed = OnshapeSketchModifyEngine.trimAtPoint(plane, const Offset(30, 10));
      expect(trimmed, isTrue);

      // Line 1 should be split at (20, 10), and the right sub-segment (20,10)->(40,10) removed,
      // leaving the left branch (0, 10)->(20, 10)
      final remaining = plane.primitives.whereType<CADLineEntity>().toList();
      expect(remaining.length, 2); // Left part of l1 + full l2
      expect(remaining.any((l) => (l.start == const Offset(0, 10) && l.end == const Offset(20, 10))), isTrue);
    });

    test('Split tool splits segment at click point', () {
      final plane = CADSketchPlane(
        id: 'plane_split',
        name: 'Split Plane',
        origin: vm_math.Vector3.zero(),
        normal: vm_math.Vector3(0, 0, 1),
        up: vm_math.Vector3(0, 1, 0),
      );

      final l1 = CADLineEntity(id: 'l_split', start: const Offset(0, 0), end: const Offset(100, 0));
      plane.primitives.add(l1);

      final didSplit = OnshapeSketchModifyEngine.splitAtPoint(plane, const Offset(40, 0));
      expect(didSplit, isTrue);

      final lines = plane.primitives.whereType<CADLineEntity>().toList();
      expect(lines.length, 2);
      expect(lines[0].start, const Offset(0, 0));
      expect(lines[0].end, const Offset(40, 0));
      expect(lines[1].start, const Offset(40, 0));
      expect(lines[1].end, const Offset(100, 0));
    });

    test('Extend tool extends line to intersecting reference line', () {
      final plane = CADSketchPlane(
        id: 'plane_extend',
        name: 'Extend Plane',
        origin: vm_math.Vector3.zero(),
        normal: vm_math.Vector3(0, 0, 1),
        up: vm_math.Vector3(0, 1, 0),
      );

      // Line pointing towards x = 50
      final lRay = CADLineEntity(id: 'l_ray', start: const Offset(0, 10), end: const Offset(20, 10));
      // Target wall at x = 50
      final lWall = CADLineEntity(id: 'l_wall', start: const Offset(50, 0), end: const Offset(50, 40));
      plane.primitives.addAll([lRay, lWall]);

      final didExtend = OnshapeSketchModifyEngine.extendAtPoint(plane, const Offset(19, 10));
      expect(didExtend, isTrue);

      final extended = plane.primitives.whereType<CADLineEntity>().firstWhere((l) => l.id == 'l_ray');
      expect(extended.end.dx, closeTo(50.0, 1e-3));
    });

    test('Offset tool (O) offsets line perpendicularly', () {
      final plane = CADSketchPlane(
        id: 'plane_offset',
        name: 'Offset Plane',
        origin: vm_math.Vector3.zero(),
        normal: vm_math.Vector3(0, 0, 1),
        up: vm_math.Vector3(0, 1, 0),
      );

      final line = CADLineEntity(id: 'line_src', start: const Offset(0, 0), end: const Offset(50, 0));
      plane.primitives.add(line);

      final offsetLine = OnshapeSketchModifyEngine.offsetEntity(plane, line, 10.0);
      expect(offsetLine, isNotNull);
      expect(offsetLine, isA<CADLineEntity>());
      final l = offsetLine as CADLineEntity;
      expect(l.start.dy, closeTo(10.0, 1e-4));
      expect(l.end.dy, closeTo(10.0, 1e-4));
    });

    test('Linear pattern generates N x M array of primitives', () {
      final plane = CADSketchPlane(
        id: 'plane_pat',
        name: 'Pattern Plane',
        origin: vm_math.Vector3.zero(),
        normal: vm_math.Vector3(0, 0, 1),
        up: vm_math.Vector3(0, 1, 0),
      );

      final circ = CADCircleEntity(id: 'c1', center: const Offset(10, 10), radius: 5);
      plane.primitives.add(circ);

      final created = OnshapeSketchModifyEngine.createSketchLinearPattern(
        plane: plane,
        sourceEntities: [circ],
        countX: 3,
        countY: 2,
        spacingXMm: 20.0,
        spacingYMm: 15.0,
      );

      // (3 * 2) - 1 original = 5 new entities
      expect(created.length, 5);
      expect(plane.primitives.length, 6);
    });

    test('Circular pattern generates radial array', () {
      final plane = CADSketchPlane(
        id: 'plane_cpat',
        name: 'Circular Pattern Plane',
        origin: vm_math.Vector3.zero(),
        normal: vm_math.Vector3(0, 0, 1),
        up: vm_math.Vector3(0, 1, 0),
      );

      final circ = CADCircleEntity(id: 'c_orig', center: const Offset(20, 0), radius: 3);
      plane.primitives.add(circ);

      final created = OnshapeSketchModifyEngine.createSketchCircularPattern(
        plane: plane,
        sourceEntities: [circ],
        center: Offset.zero,
        instanceCount: 4,
        totalAngleDeg: 360.0,
      );

      expect(created.length, 3);
      expect(plane.primitives.length, 4);
    });
  });

  group('Onshape Constraint Solver & Audit Root Cause Tests', () {
    test('Midpoint constraint snaps point to line midpoint', () {
      final plane = CADSketchPlane(
        id: 'plane_cst',
        name: 'Constraint Plane',
        origin: vm_math.Vector3.zero(),
        normal: vm_math.Vector3(0, 0, 1),
        up: vm_math.Vector3(0, 1, 0),
      );

      final line = CADLineEntity(id: 'l1', start: const Offset(0, 0), end: const Offset(100, 0));
      final pt = CADPointEntity(id: 'p1', position: const Offset(10, 50));
      plane.primitives.addAll([line, pt]);

      final cst = CadConstraint(
        id: 'cst_mid',
        type: CadConstraintType.midpoint,
        entityIds: ['l1', 'p1'],
      );
      plane.constraints.add(cst);

      final solved = AssemblySketchConstraintSolver.solve(plane);
      expect(solved.isSuccess, isTrue);

      final pAfter = plane.primitives.whereType<CADPointEntity>().first;
      expect(pAfter.position.dx, closeTo(50.0, 1e-4));
      expect(pAfter.position.dy, closeTo(0.0, 1e-4));
    });

    test('Drawing 2D curves never prematurely adds 3D features to part.sketches (Fix 2)', () {
      final vm = AssemblyStudioViewModel();
      expect(vm.doc.parts, isNotEmpty);
      final part = vm.doc.parts.first;
      final initialSketchesCount = part.sketches.length;

      vm.focusPartAndEnterSketch(part.id);

      // Draw 2 circles on the sketch plane
      vm.addPrimitiveEntityToActivePlane(CADCircleEntity(id: 'c1', center: const Offset(10, 10), radius: 5));
      vm.addPrimitiveEntityToActivePlane(CADCircleEntity(id: 'c2', center: const Offset(30, 10), radius: 5));

      // Part sketches must NOT have mutated while drawing in 2D!
      expect(part.sketches.length, initialSketchesCount);
      expect(vm.activeSketchPlane!.primitives.length, 2);
    });

    test('Multi-Profile Loop Validation detects all closed loops cleanly (Fix 3)', () {
      final plane = CADSketchPlane(
        id: 'plane_multi',
        name: 'Multi-Loop Plane',
        origin: vm_math.Vector3.zero(),
        normal: vm_math.Vector3(0, 0, 1),
        up: vm_math.Vector3(0, 1, 0),
      );

      // Loop 1: Outer rectangle
      final rOuter = CADRectangleEntity(id: 'r_outer', startPoint: const Offset(0, 0), width: 100, height: 80);
      // Loop 2: Inner circular hole
      final rInner = CADCircleEntity(id: 'c_inner', center: const Offset(50, 40), radius: 15);
      plane.primitives.addAll([rOuter, rInner]);

      final validation = AssemblySurfaceSketchEngine.validatePlaneLoop(plane);
      expect(validation.isValidClosedLoop, isTrue);
      expect(validation.allClosedLoops.length, 2);
      expect(validation.reportFeedback, contains('Closed Profile(s) Ready'));
    });
  });
}
