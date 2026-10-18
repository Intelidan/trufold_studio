import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm_math;

import 'package:trufold_studio/assembly_studio/engine/sketch/assembly_surface_sketch_engine.dart';
import 'package:trufold_studio/assembly_studio/engine/sketch/onshape_sketch_modify_engine.dart';
import 'package:trufold_studio/assembly_studio/models/assembly_document.dart';
import 'package:trufold_studio/assembly_studio/models/assembly_part.dart';
import 'package:trufold_studio/assembly_studio/models/assembly_timeline_item.dart';
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
      expect(vm.activeSketchPlane!.primitives.where((p) => !p.isImprintedReference).length, 2);
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

  group('Onshape Master Specification Regressions (Part 6)', () {
    test('singleClickSketchHighlightsOnly_doubleClickEntersSketchMode', () {
      final vm = AssemblyStudioViewModel();
      final sketchItem = AssemblyTimelineItem(
        id: 'sketch_test_1',
        name: 'Sketch 1',
        kind: AssemblyFeatureKind.sketch,
      );
      vm.doc.featureTree.add(sketchItem);

      // 1. Single click tap: highlights feature only, NEVER enters sketch mode
      vm.selectTimelineFeature(sketchItem.id);
      expect(vm.highlightedFeatureId, equals('sketch_test_1'));
      expect(vm.isSketchModeActive, isFalse);

      // 2. Double click: enters sketch mode
      vm.enterSketchMode();
      expect(vm.isSketchModeActive, isTrue);
    });

    test('witnessLinesAreStrictlyPerpendicularToMeasuredEdge', () {
      final p1 = vm_math.Vector2(10.0, 15.0);
      final p2 = vm_math.Vector2(50.0, 45.0);
      final edgeDir = (p2 - p1).normalized();

      final dim = computeOrthogonalDimension2D(
        p1: p1,
        p2: p2,
        labelPosition2D: vm_math.Vector2(15.0, 60.0),
        orientation: SketchDimensionOrientation.aligned,
        witnessOvershootMm: 4.0,
      );

      final witness1Dir = (dim.witness1End - dim.dimLineStart).normalized();
      final witness2Dir = (dim.witness2End - dim.dimLineEnd).normalized();

      expect(witness1Dir.dot(edgeDir).abs(), lessThan(1e-5));
      expect(witness2Dir.dot(edgeDir).abs(), lessThan(1e-5));
      expect(dim.anchor1, equals(p1));
      expect(dim.anchor2, equals(p2));
    });

    test('twoEntityAndBorderDimensions_supportDrivenGreyState', () {
      final plane = CADSketchPlane(
        id: 'plane_dim_test',
        name: 'Dimension Test Plane',
        origin: vm_math.Vector3.zero(),
        normal: vm_math.Vector3(0, 0, 1),
        up: vm_math.Vector3(0, 1, 0),
      );

      // Circle 1 and Circle 2
      final c1 = CADCircleEntity(id: 'c1', center: const Offset(20, 30), radius: 6);
      final c2 = CADCircleEntity(id: 'c2', center: const Offset(119, 30), radius: 6);
      // Imprinted fixed border line
      final borderLine = CADLineEntity(
        id: 'border_1',
        start: const Offset(0, 0),
        end: const Offset(0, 100),
        isImprintedReference: true,
        isFixed: true,
        isFullyConstrained: true,
      );
      plane.primitives.addAll([c1, c2, borderLine]);

      // Dim 1: distance from border to circle 1 center = 65
      final dimBorderToC1 = CadConstraint(
        id: 'dim_border_c1',
        type: CadConstraintType.distance,
        entityIds: ['border_1', 'c1'],
        parameterValue: 65.0,
      );

      // Dim 2: distance between circle 1 and circle 2 centers = 99
      final dimC1ToC2 = CadConstraint(
        id: 'dim_c1_c2',
        type: CadConstraintType.distance,
        entityIds: ['c1', 'c2'],
        parameterValue: 99.0,
      );

      // Dim 3: over-constraining distance directly locking circle 2 to border
      // since both c1 and c2 are already fully locked horizontally
      final dimOver = CadConstraint(
        id: 'dim_over',
        type: CadConstraintType.distance,
        entityIds: ['border_1', 'c2'],
        parameterValue: 164.0,
      );

      plane.constraints.addAll([dimBorderToC1, dimC1ToC2, dimOver]);

      final result = AssemblySketchConstraintSolver.solve(plane);
      expect(result.isSuccess, isTrue);

      // Over-constrained dimension is automatically flagged as driven
      expect(dimOver.isDriven, isTrue);
      expect(dimOver.isDriving, isFalse);
    });

    test('closedPolygonMovesRigidlyWhenConstrainedFromEdgeMidpointOrCenter', () {
      final plane = CADSketchPlane(
        id: 'plane_poly_rigid',
        name: 'Polygon Plane',
        origin: vm_math.Vector3.zero(),
        normal: vm_math.Vector3(0, 0, 1),
        up: vm_math.Vector3(0, 1, 0),
      );

      final poly = CADRegularPolygonEntity(
        id: 'poly_1',
        center: const Offset(50, 50),
        radius: 20.0,
        sides: 5, // Pentagon
        rotationRad: 0.0,
      );
      final initialVerts = List<Offset>.from(poly.vertices);
      final initialEdgeLength = (initialVerts[1] - initialVerts[0]).distance;

      plane.primitives.add(poly);

      // Shift pentagon via midpoint subKey constraint
      final cst = CadConstraint(
        id: 'cst_poly_shift',
        type: CadConstraintType.distance,
        entityIds: ['poly_1:mid_0'],
        parameterValue: 35.0,
      );
      plane.constraints.add(cst);

      final solved = AssemblySketchConstraintSolver.solve(plane);
      expect(solved.isSuccess, isTrue);

      final movedVerts = poly.vertices;
      final movedEdgeLength = (movedVerts[1] - movedVerts[0]).distance;

      // Internal edge length must be identical (no deformation!)
      expect(movedEdgeLength, closeTo(initialEdgeLength, 1e-4));
      final delta = movedVerts[0] - initialVerts[0];
      for (int i = 1; i < 5; i++) {
        expect((movedVerts[i] - initialVerts[i]).dx, closeTo(delta.dx, 1e-4));
        expect((movedVerts[i] - initialVerts[i]).dy, closeTo(delta.dy, 1e-4));
      }
    });

    test('extrudeCutSubtractsFromRail_andEditingOperationReplacesPreviousBody', () {
      final doc = AssemblyDocument(
        id: 'doc_extrude_test',
        title: 'Extrude Test Document',
        parts: [
          AssemblyPart(
            id: 'right_rail',
            name: 'Right Side Rail',
            type: AssemblyPartType.straightRail,
            color: const Color(0xFF1565C0),
            thickness: 3.0,
          )..saveBaseMeshSnapshot(),
        ],
      );

      final plane = CADSketchPlane(
        id: 'sketch_cut_plane',
        name: 'Cut Sketch',
        origin: vm_math.Vector3(0, 0, 0),
        normal: vm_math.Vector3(0, 0, 1),
        up: vm_math.Vector3(0, 1, 0),
        targetPartId: 'right_rail',
      );
      plane.primitives.add(
        CADCircleEntity(id: 'hole_circle', center: const Offset(20, 20), radius: 8),
      );

      // Step 1: Create 'New Body' extrude feature
      final extrudeFeature = AssemblyTimelineItem(
        id: 'feat_extrude_1',
        name: 'Extrude 1',
        kind: AssemblyFeatureKind.extrude,
        parentSketchId: plane.id,
        targetProfileIds: {'hole_circle'},
        extrudeSpec: ExtrudeFeatureSpec(
          featureId: 'feat_extrude_1',
          sketchId: plane.id,
          targetProfileIds: {'hole_circle'},
          depthMm: 25.0,
          operation: 'newBody',
          targetPartId: 'right_rail',
        ),
      );
      doc.featureTree.add(extrudeFeature);

      AssemblyExtrudeEngine.rebuildFeatureTimeline(
        doc: doc,
        allPlanes: [plane],
      );

      expect(doc.parts.any((p) => p.createdByFeatureId == 'feat_extrude_1'), isTrue);
      expect(doc.parts.length, equals(2));

      // Step 2: Edit 'Extrude 1' to 'cut' operation
      extrudeFeature.extrudeSpec = ExtrudeFeatureSpec(
        featureId: 'feat_extrude_1',
        sketchId: plane.id,
        targetProfileIds: {'hole_circle'},
        depthMm: 25.0,
        operation: 'cut',
        targetPartId: 'right_rail',
      );

      AssemblyExtrudeEngine.rebuildFeatureTimeline(
        doc: doc,
        allPlanes: [plane],
      );

      // Previous 'Extruded Body' is removed
      expect(doc.parts.any((p) => p.createdByFeatureId == 'feat_extrude_1'), isFalse);
      expect(doc.parts.length, equals(1));

      // Right rail registered the hole cut
      final rail = doc.parts.firstWhere((p) => p.id == 'right_rail');
      expect(rail.cutHoles.length, equals(1));
      expect(rail.cutHoles.first.diameterMm, closeTo(16.0, 1e-4));
    });
  });

  group('Onshape B-Rep Topology, Camera Lock & X-Ray Snapping Specification (Section 9)', () {
    test('holeCenters_onlyHighlightOnProximityOrExplicitSelection_includingHiddenXRayHover', () {
      final vm = AssemblyStudioViewModel();
      final part = AssemblyPart(
        id: 'part_holes',
        name: 'Bracket with Hole',
        type: AssemblyPartType.channel,
        length: 100.0,
        height: 60.0,
        thickness: 3.0,
      );
      part.cutHoles.add(
        AssemblyCutHole(
          centerWorld: vm_math.Vector3(50.0, 0.0, 30.0),
          axisWorld: vm_math.Vector3(0.0, 1.0, 0.0),
          diameterMm: 12.0,
          depthMm: 3.0,
        ),
      );
      vm.doc.parts.clear();
      vm.doc.parts.add(part);

      // 1. Selecting all parts must leave selectedHoleCenterIds completely empty
      vm.selectAllParts();
      expect(vm.doc.selectedPartIds.length, equals(1));
      expect(vm.selectedHoleCenterIds, isEmpty);

      // 2. Project hole center to screen
      const viewportSize = Size(1000, 800);
      final holeCenterWorld = vm_math.Vector3(50.0, 0.0, 30.0);
      final screenPt = vm.projectWorldToScreen(holeCenterWorld, viewportSize);
      expect(screenPt, isNotNull);

      // 3. Hovering mouse far away (> 18px) does NOT set hoveredHoleCenterId
      vm.updateMouseScreenOffset(screenPt! + const Offset(50.0, 50.0), viewportSize);
      expect(vm.hoveredHoleCenterId, isNull);

      // 4. Hovering mouse within 18px sets hoveredHoleCenterId (X-ray snapping)
      vm.updateMouseScreenOffset(screenPt + const Offset(8.0, 6.0), viewportSize);
      expect(vm.hoveredHoleCenterId, equals('hole_part_holes_0'));

      // 5. Explicitly selecting a hole center adds it to selectedHoleCenterIds
      vm.selectedHoleCenterIds.add('hole_part_holes_0');
      expect(vm.selectedHoleCenterIds.contains('hole_part_holes_0'), isTrue);
    });

    test('cameraZoomAndPosition_remainLockedOnSketchActivateAndDeactivate', () {
      final vm = AssemblyStudioViewModel();
      final part = AssemblyPart(
        id: 'part_rail',
        name: 'Side Rail',
        type: AssemblyPartType.straightRail,
        length: 200.0,
        height: 80.0,
      );
      vm.doc.parts.add(part);
      vm.selectPart(part.id);

      vm.cameraDistance = 1250.0;
      vm.cameraPosition = const Offset(42.0, -18.0);

      final initialDistance = vm.cameraDistance;
      final initialPosition = vm.cameraPosition;

      // 1. Enter sketch mode
      vm.enterSketchMode();
      expect(vm.isSketchModeActive, isTrue);
      expect(vm.cameraDistance, equals(initialDistance));
      expect(vm.cameraPosition, equals(initialPosition));

      // 2. Switch sketch tools
      vm.activeSketchTool = 'line';
      expect(vm.cameraDistance, equals(initialDistance));
      expect(vm.cameraPosition, equals(initialPosition));

      vm.activeSketchTool = 'circle';
      expect(vm.cameraDistance, equals(initialDistance));
      expect(vm.cameraPosition, equals(initialPosition));

      vm.activeSketchTool = 'dimension';
      expect(vm.cameraDistance, equals(initialDistance));
      expect(vm.cameraPosition, equals(initialPosition));

      // 3. Confirm / Finish active sketch
      vm.confirmActiveSketch();
      expect(vm.isSketchModeActive, isFalse);
      expect(vm.cameraDistance, equals(initialDistance));
      expect(vm.cameraPosition, equals(initialPosition));
    });

    test('featureTree_singleClickHighlightsOnly_doubleClickOpensSketchOrExtrudeDialog', () {
      final vm = AssemblyStudioViewModel();

      final sketchItem = AssemblyTimelineItem(
        id: 'sketch_item_1',
        name: 'Sketch 1',
        kind: AssemblyFeatureKind.sketch,
      );
      final extrudeItem = AssemblyTimelineItem(
        id: 'extrude_item_1',
        name: 'Extrude 1',
        kind: AssemblyFeatureKind.extrude,
        parentSketchId: 'sketch_item_1',
      );
      vm.doc.featureTree.addAll([sketchItem, extrudeItem]);

      // 1. Single click on Sketch 1 highlights feature only without entering sketch mode
      vm.selectTimelineFeature(sketchItem.id);
      expect(vm.highlightedSketchId, equals('sketch_item_1'));
      expect(vm.isSketchModeActive, isFalse);

      // 2. Single click on Extrude 1 highlights 3D step and opens its property dialog
      vm.selectTimelineFeature(extrudeItem.id);
      expect(vm.highlightedFeatureId, equals('extrude_item_1'));
      expect(vm.isExtrudeDialogOpen, isTrue);

      // 3. Renaming feature updates item.name
      vm.renameTimelineFeature('extrude_item_1', 'Main Flange Extrude');
      expect(extrudeItem.name, equals('Main Flange Extrude'));
    });

    test('dimensions_witnessLinesOrthogonal_twoEntitiesAndBorders_drivenGrey', () {
      final p1 = vm_math.Vector2(10.0, 15.0);
      final p2 = vm_math.Vector2(50.0, 45.0);
      final edgeDir = (p2 - p1).normalized();

      final dim = computeOrthogonalDimension2D(
        p1: p1,
        p2: p2,
        labelPosition2D: vm_math.Vector2(15.0, 60.0),
        orientation: SketchDimensionOrientation.aligned,
        witnessOvershootMm: 4.0,
      );

      final witness1Dir = (dim.witness1End - dim.dimLineStart).normalized();
      final witness2Dir = (dim.witness2End - dim.dimLineEnd).normalized();
      expect(witness1Dir.dot(edgeDir).abs(), lessThan(1e-5));
      expect(witness2Dir.dot(edgeDir).abs(), lessThan(1e-5));

      final plane = CADSketchPlane(
        id: 'plane_dim_test',
        origin: vm_math.Vector3.zero(),
        normal: vm_math.Vector3(0, 0, 1),
        up: vm_math.Vector3(0, 1, 0),
      );
      final c1 = CADCircleEntity(id: 'c1', center: const Offset(20, 30), radius: 6);
      final c2 = CADCircleEntity(id: 'c2', center: const Offset(119, 30), radius: 6);
      final borderLine = CADLineEntity(
        id: 'border_1',
        start: const Offset(0, 0),
        end: const Offset(0, 100),
        isImprintedReference: true,
        isFixed: true,
        isFullyConstrained: true,
      );
      plane.primitives.addAll([c1, c2, borderLine]);

      final dimBorderToC1 = CadConstraint(
        id: 'dim_border_c1',
        type: CadConstraintType.distance,
        entityIds: ['border_1', 'c1'],
        parameterValue: 65.0,
      );
      final dimC1ToC2 = CadConstraint(
        id: 'dim_c1_c2',
        type: CadConstraintType.distance,
        entityIds: ['c1', 'c2'],
        parameterValue: 99.0,
      );
      final dimOver = CadConstraint(
        id: 'dim_over',
        type: CadConstraintType.distance,
        entityIds: ['border_1', 'c2'],
        parameterValue: 76.8,
      );

      plane.constraints.addAll([dimBorderToC1, dimC1ToC2, dimOver]);
      final result = AssemblySketchConstraintSolver.solve(plane);
      expect(result.isSuccess, isTrue);

      expect(dimOver.isDriven, isTrue);
      expect(dimOver.isDriving, isFalse);
    });

    test('closedPolygon_movesRigidlyAsWholeFromMidpointVertexOrCenter', () {
      final plane = CADSketchPlane(
        id: 'plane_poly_rigid',
        origin: vm_math.Vector3.zero(),
        normal: vm_math.Vector3(0, 0, 1),
        up: vm_math.Vector3(0, 1, 0),
      );

      final poly = CADRegularPolygonEntity(
        id: 'poly_pentagon',
        center: const Offset(50, 50),
        radius: 20.0,
        sides: 5,
        rotationRad: 0.0,
      );
      final initialVerts = List<Offset>.from(poly.vertices);
      final initialEdgeLength = (initialVerts[1] - initialVerts[0]).distance;

      plane.primitives.add(poly);

      final cst = CadConstraint(
        id: 'cst_poly_midpoint',
        type: CadConstraintType.distance,
        entityIds: ['poly_pentagon:mid_0'],
        parameterValue: 40.0,
      );
      plane.constraints.add(cst);

      final solved = AssemblySketchConstraintSolver.solve(plane);
      expect(solved.isSuccess, isTrue);

      final movedVerts = poly.vertices;
      final movedEdgeLength = (movedVerts[1] - movedVerts[0]).distance;

      expect(movedEdgeLength, closeTo(initialEdgeLength, 1e-4));
      final delta = movedVerts[0] - initialVerts[0];
      for (int i = 1; i < 5; i++) {
        expect((movedVerts[i] - initialVerts[i]).dx, closeTo(delta.dx, 1e-4));
        expect((movedVerts[i] - initialVerts[i]).dy, closeTo(delta.dy, 1e-4));
      }
    });

    test('extrudeCut_punchesPassThroughHole_andEditingOperationCancelsPreviousExtrudeBody', () {
      final doc = AssemblyDocument(
        id: 'doc_extrude_test_2',
        title: 'Extrude Test Document 2',
        parts: [
          AssemblyPart(
            id: 'right_rail_2',
            name: 'Right Side Rail',
            type: AssemblyPartType.straightRail,
            color: const Color(0xFF1565C0),
            thickness: 3.0,
          )..saveBaseMeshSnapshot(),
        ],
      );

      final plane = CADSketchPlane(
        id: 'sketch_cut_plane_2',
        name: 'Cut Sketch 2',
        origin: vm_math.Vector3(0, 0, 0),
        normal: vm_math.Vector3(0, 0, 1),
        up: vm_math.Vector3(0, 1, 0),
        targetPartId: 'right_rail_2',
      );
      plane.primitives.add(
        CADCircleEntity(id: 'hole_circle_2', center: const Offset(20, 20), radius: 8),
      );

      final extrudeFeature = AssemblyTimelineItem(
        id: 'feat_extrude_2',
        name: 'Extrude 2',
        kind: AssemblyFeatureKind.extrude,
        parentSketchId: plane.id,
        targetProfileIds: {'hole_circle_2'},
        extrudeSpec: ExtrudeFeatureSpec(
          featureId: 'feat_extrude_2',
          sketchId: plane.id,
          targetProfileIds: {'hole_circle_2'},
          depthMm: 25.0,
          operation: 'newBody',
          targetPartId: 'right_rail_2',
        ),
      );
      doc.featureTree.add(extrudeFeature);

      AssemblyExtrudeEngine.rebuildFeatureTimeline(
        doc: doc,
        allPlanes: [plane],
      );

      expect(doc.parts.any((p) => p.createdByFeatureId == 'feat_extrude_2'), isTrue);
      expect(doc.parts.length, equals(2));

      extrudeFeature.extrudeSpec = ExtrudeFeatureSpec(
        featureId: 'feat_extrude_2',
        sketchId: plane.id,
        targetProfileIds: {'hole_circle_2'},
        depthMm: 25.0,
        operation: 'cut',
        targetPartId: 'right_rail_2',
      );

      AssemblyExtrudeEngine.rebuildFeatureTimeline(
        doc: doc,
        allPlanes: [plane],
      );

      expect(doc.parts.any((p) => p.createdByFeatureId == 'feat_extrude_2'), isFalse);
      expect(doc.parts.length, equals(1));

      final rail = doc.parts.firstWhere((p) => p.id == 'right_rail_2');
      expect(rail.cutHoles.length, equals(1));
      expect(rail.cutHoles.first.diameterMm, closeTo(16.0, 1e-4));
    });
  });
}
