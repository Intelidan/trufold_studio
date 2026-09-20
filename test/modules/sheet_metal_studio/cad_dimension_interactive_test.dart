// =============================================================================
// cad_dimension_interactive_test.dart
//
// Comprehensive test suite for Onshape-style interactive 2-entity constraint
// dimensioning, inline badge triggering, and direct dimension driving:
// 1. CadDimension data model (CadAnchorType, CadAllowedMotion, resolveAnchorPoint).
// 2. MagneticSnapEngine entityId tagging.
// 3. 2-click interactive dimensioning in SheetMetalStudioViewModel.
// 4. Direct driving of Hole-to-Hole pitch and Hole-to-Edge setback.
// 5. Dependent constraint chain propagation.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_dimension.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_constraint.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_feature.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cnc_punch_primitive.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/fold_bend_line.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/magnetic_snap_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/associative_dimension_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/cad_property_inspector.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/punch_property_sheet.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/dimension_property_sheet.dart';

void main() {
  group('1. CadDimension Model & Anchor Point Resolution', () {
    test('CadAnchorType symbols and labels match Onshape CAD standards', () {
      expect(CadAnchorType.center.symbol, equals('⊙'));
      expect(CadAnchorType.center.label, equals('Center'));
      expect(CadAnchorType.midpoint.symbol, equals('⌖'));
      expect(CadAnchorType.midpoint.label, equals('Midpoint'));
      expect(CadAnchorType.endpoint.symbol, equals('•'));
      expect(CadAnchorType.arcMidpoint.symbol, equals('⊕'));
      expect(CadAnchorType.quadrant.symbol, equals('◇'));
      expect(CadAnchorType.perpendicular.symbol, equals('⊥'));
    });

    test('CadDimension JSON serialization round-trips constraint fields', () {
      const dim = CadDimension(
        id: 'dim_1',
        type: CadDimensionType.holeToHole,
        referenceAId: 'P1',
        referenceBId: 'P2',
        anchorTypeA: CadAnchorType.center,
        anchorTypeB: CadAnchorType.center,
        pointA: CadPoint2D(10, 20),
        pointB: CadPoint2D(60, 20),
        measuredValue: 50.0,
        isDriving: true,
        allowedMotion: CadAllowedMotion.constraintVector,
        referenceEntityId: 'P1',
        drivenEntityId: 'P2',
      );

      final json = dim.toJson();
      final restored = CadDimension.fromJson(json);

      expect(restored.id, equals('dim_1'));
      expect(restored.type, equals(CadDimensionType.holeToHole));
      expect(restored.referenceAId, equals('P1'));
      expect(restored.referenceBId, equals('P2'));
      expect(restored.anchorTypeA, equals(CadAnchorType.center));
      expect(restored.anchorTypeB, equals(CadAnchorType.center));
      expect(restored.isDriving, isTrue);
      expect(restored.allowedMotion, equals(CadAllowedMotion.constraintVector));
      expect(restored.referenceEntityId, equals('P1'));
      expect(restored.drivenEntityId, equals('P2'));
      expect(restored.measuredValue, equals(50.0));
    });

    test('resolveAnchorPoint correctly resolves live positions from document', () {
      const doc = DsfDocument(
        productType: 'Test Part',
        itemName: 'TEST-01',
        outerContour: [
          CadPoint2D(0, 0),
          CadPoint2D(200, 0),
          CadPoint2D(200, 300),
          CadPoint2D(0, 300),
        ],
        punches: [
          CncPunchPrimitive(
            id: 'P1',
            type: PunchType.roundHole,
            center: CadPoint2D(40, 50),
            diameterMm: 10,
          ),
        ],
        bends: [
          FoldBendLine(
            id: 'B1',
            p1: CadPoint2D(0, 100),
            p2: CadPoint2D(200, 100),
            targetAngleDeg: 90,
            radiusMm: 1.5,
          ),
        ],
      );

      // Punch center
      final punchCenter = CadDimension.resolveAnchorPoint(
        doc: doc,
        entityId: 'P1',
        anchorType: CadAnchorType.center,
      );
      expect(punchCenter, equals(const CadPoint2D(40, 50)));

      // Bend midpoint
      final bendMid = CadDimension.resolveAnchorPoint(
        doc: doc,
        entityId: 'B1',
        anchorType: CadAnchorType.midpoint,
      );
      expect(bendMid, equals(const CadPoint2D(100, 100)));

      // Contour edge midpoint
      final edgeMid = CadDimension.resolveAnchorPoint(
        doc: doc,
        entityId: 'CONTOUR_EDGE_0',
        anchorType: CadAnchorType.midpoint,
      );
      expect(edgeMid, equals(const CadPoint2D(100, 0)));
    });
  });

  group('2. MagneticSnapEngine Entity ID Tagging', () {
    test('Snap targets contain correct entityId for punches, bends, cuts, and contour', () {
      const doc = DsfDocument(
        productType: 'Test Part',
        itemName: 'TEST-01',
        outerContour: [
          CadPoint2D(0, 0),
          CadPoint2D(200, 0),
          CadPoint2D(200, 300),
          CadPoint2D(0, 300),
        ],
        punches: [
          CncPunchPrimitive(
            id: 'P1',
            type: PunchType.roundHole,
            center: CadPoint2D(50, 50),
            diameterMm: 10,
          ),
        ],
        bends: [
          FoldBendLine(
            id: 'B1',
            p1: CadPoint2D(0, 100),
            p2: CadPoint2D(200, 100),
            targetAngleDeg: 90,
            radiusMm: 1.5,
          ),
        ],
        cutLines: [
          CadLineSegment(
            id: 'C1',
            p1: CadPoint2D(50, 200),
            p2: CadPoint2D(150, 200),
          ),
        ],
      );

      final targets = MagneticSnapEngine.extractTargets(doc);

      // Test snap to punch center
      final punchSnap = MagneticSnapEngine.findClosestSnap(
        cursorMm: const CadPoint2D(51, 49),
        targets: targets,
        doc: doc,
        snapRadiusMm: 8.0,
      );
      expect(punchSnap, isNotNull);
      expect(punchSnap!.entityId, equals('P1'));
      expect(punchSnap.type, equals(SnapType.punchCenter));

      // Test snap to bend midpoint
      final bendSnap = MagneticSnapEngine.findClosestSnap(
        cursorMm: const CadPoint2D(100, 101),
        targets: targets,
        doc: doc,
        snapRadiusMm: 8.0,
      );
      expect(bendSnap, isNotNull);
      expect(bendSnap!.entityId, equals('B1'));
      expect(bendSnap.type, equals(SnapType.edgeMidpoint));

      // Test snap to cut line endpoint
      final cutSnap = MagneticSnapEngine.findClosestSnap(
        cursorMm: const CadPoint2D(50.5, 200.5),
        targets: targets,
        doc: doc,
        snapRadiusMm: 8.0,
      );
      expect(cutSnap, isNotNull);
      expect(cutSnap!.entityId, equals('C1'));
    });
  });

  group('3. Interactive 2-Click Dimensioning & Direct Driving', () {
    late SheetMetalStudioViewModel vm;

    setUp(() {
      vm = SheetMetalStudioViewModel();
      const doc = DsfDocument(
        productType: 'Test Part',
        itemName: 'TEST-01',
        outerContour: [
          CadPoint2D(0, 0),
          CadPoint2D(200, 0),
          CadPoint2D(200, 300),
          CadPoint2D(0, 300),
        ],
        bends: [],
        punches: [
          CncPunchPrimitive(
            id: 'P1',
            type: PunchType.roundHole,
            center: CadPoint2D(50, 50),
            diameterMm: 10,
          ),
          CncPunchPrimitive(
            id: 'P2',
            type: PunchType.roundHole,
            center: CadPoint2D(150, 50),
            diameterMm: 10,
          ),
        ],
      );
      vm.loadDocument(doc);
    });

    test('2-click workflow creates Hole-to-Hole dimension and sets pending in-place edit ID', () {
      vm.setToolMode(StudioToolMode.addDimension);

      // Click 1: Near Punch P1 center
      vm.updateCursorMm(const CadPoint2D(51, 50));
      vm.handleCanvasClick(const CadPoint2D(51, 50));

      expect(vm.pendingDimensionEntityAId, equals('P1'));
      expect(vm.pendingDimensionAnchorTypeA, equals(CadAnchorType.center));
      expect(vm.pendingBendStart, equals(const CadPoint2D(50, 50)));

      // Click 2: Near Punch P2 center
      vm.updateCursorMm(const CadPoint2D(149, 51));
      vm.handleCanvasClick(const CadPoint2D(149, 51));

      expect(vm.document.dimensions.length, equals(1));
      final dim = vm.document.dimensions.first;
      expect(dim.type, equals(CadDimensionType.holeToHole));
      expect(dim.referenceAId, equals('P1'));
      expect(dim.referenceBId, equals('P2'));
      expect(dim.isDriving, isTrue);
      expect(dim.allowedMotion, equals(CadAllowedMotion.constraintVector));
      expect(dim.measuredValue, closeTo(100.0, 0.01));

      // Inline editable badge pending ID is set
      expect(vm.pendingInPlaceEditDimId, equals(dim.id));
      expect(vm.toolMode, equals(StudioToolMode.select));
    });

    test('Direct driving Hole-to-Hole dimension translates driven punch along constraint vector', () {
      vm.setToolMode(StudioToolMode.addDimension);
      vm.updateCursorMm(const CadPoint2D(50, 50));
      vm.handleCanvasClick(const CadPoint2D(50, 50));
      vm.updateCursorMm(const CadPoint2D(150, 50));
      vm.handleCanvasClick(const CadPoint2D(150, 50));

      final dim = vm.document.dimensions.first;
      expect(dim.measuredValue, closeTo(100.0, 0.01));

      // User enters new distance: 130mm
      vm.driveDimension(dim.id, 130.0);

      // Driven punch P2 should move by +30mm along X
      final p1 = vm.document.punches.firstWhere((p) => p.id == 'P1');
      final p2 = vm.document.punches.firstWhere((p) => p.id == 'P2');
      expect(p1.center, equals(const CadPoint2D(50, 50))); // Fixed reference
      expect(p2.center.x, closeTo(180.0, 0.01)); // 50 + 130
      expect(p2.center.y, closeTo(50.0, 0.01));

      // Rigid geometry invariant: diameter remains 10mm
      expect(p2.diameterMm, equals(10.0));

      // Dimension measuredValue is updated to 130mm
      final updatedDim = vm.document.dimensions.firstWhere((d) => d.id == dim.id);
      expect(updatedDim.measuredValue, closeTo(130.0, 0.01));
    });

    test('Direct driving Hole-to-Edge dimension translates punch along edge normal', () {
      vm.setToolMode(StudioToolMode.addDimension);

      // Click 1: Punch P1 at (50, 50)
      vm.updateCursorMm(const CadPoint2D(50, 50));
      vm.handleCanvasClick(const CadPoint2D(50, 50));

      // Click 2: Bottom contour edge (Y = 0)
      vm.updateCursorMm(const CadPoint2D(50, 2));
      vm.handleCanvasClick(const CadPoint2D(50, 2));

      expect(vm.document.dimensions.length, equals(1));
      final dim = vm.document.dimensions.first;
      expect(dim.type, equals(CadDimensionType.holeToEdge));
      expect(dim.allowedMotion, equals(CadAllowedMotion.edgeNormal));
      expect(dim.measuredValue, closeTo(50.0, 0.01));

      // User enters new setback: 75mm
      vm.driveDimension(dim.id, 75.0);

      final p1 = vm.document.punches.firstWhere((p) => p.id == 'P1');
      expect(p1.center.x, closeTo(50.0, 0.01));
      expect(p1.center.y, closeTo(75.0, 0.01)); // Setback updated along normal
      expect(p1.diameterMm, equals(10.0)); // Rigid geometry invariant
    });

    test('Dependent punch constraint chain propagation', () {
      // Create a 3-punch chain: P1 -> P2 -> P3
      const doc = DsfDocument(
        productType: 'Test Part',
        itemName: 'TEST-01',
        outerContour: [
          CadPoint2D(0, 0),
          CadPoint2D(300, 0),
          CadPoint2D(300, 300),
          CadPoint2D(0, 300),
        ],
        bends: [],
        punches: [
          CncPunchPrimitive(
            id: 'P1',
            type: PunchType.roundHole,
            center: CadPoint2D(50, 50),
            diameterMm: 10,
          ),
          CncPunchPrimitive(
            id: 'P2',
            type: PunchType.roundHole,
            center: CadPoint2D(100, 50),
            diameterMm: 10,
          ),
          CncPunchPrimitive(
            id: 'P3',
            type: PunchType.roundHole,
            center: CadPoint2D(150, 50),
            diameterMm: 10,
          ),
        ],
        dimensions: [
          CadDimension(
            id: 'dim_p1_p2',
            type: CadDimensionType.holeToHole,
            referenceAId: 'P1',
            referenceBId: 'P2',
            referenceEntityId: 'P1',
            drivenEntityId: 'P2',
            pointA: CadPoint2D(50, 50),
            pointB: CadPoint2D(100, 50),
            measuredValue: 50.0,
            isDriving: true,
            allowedMotion: CadAllowedMotion.constraintVector,
          ),
          CadDimension(
            id: 'dim_p2_p3',
            type: CadDimensionType.holeToHole,
            referenceAId: 'P2',
            referenceBId: 'P3',
            referenceEntityId: 'P2',
            drivenEntityId: 'P3',
            pointA: CadPoint2D(100, 50),
            pointB: CadPoint2D(150, 50),
            measuredValue: 50.0,
            isDriving: true,
            allowedMotion: CadAllowedMotion.constraintVector,
          ),
        ],
      );
      vm.loadDocument(doc);

      // Drive P1->P2 pitch from 50mm to 80mm (+30mm)
      vm.driveDimension('dim_p1_p2', 80.0);

      final p1 = vm.document.punches.firstWhere((p) => p.id == 'P1');
      final p2 = vm.document.punches.firstWhere((p) => p.id == 'P2');
      final p3 = vm.document.punches.firstWhere((p) => p.id == 'P3');

      expect(p1.center.x, closeTo(50.0, 0.01)); // Fixed reference
      expect(p2.center.x, closeTo(130.0, 0.01)); // 50 + 80 = 130
      // P3 propagates along the chain: moved from 150 to 180!
      expect(p3.center.x, closeTo(180.0, 0.01)); // 150 + 30 = 180
    });
  });

  group('6. Selection State Isolation & Orthogonal Dimension Layout', () {
    late SheetMetalStudioViewModel vm;

    setUp(() {
      vm = SheetMetalStudioViewModel();
      const doc = DsfDocument(
        productType: 'Test Part',
        itemName: 'TEST-01',
        outerContour: [
          CadPoint2D(0, 0),
          CadPoint2D(300, 0),
          CadPoint2D(300, 300),
          CadPoint2D(0, 300),
        ],
        bends: [
          FoldBendLine(
            id: 'B1',
            p1: CadPoint2D(10, 0),
            p2: CadPoint2D(10, 300),
            targetAngleDeg: 90,
            radiusMm: 1.5,
          ),
        ],
        punches: [
          CncPunchPrimitive(
            id: 'P1',
            type: PunchType.roundHole,
            center: CadPoint2D(50, 100),
            diameterMm: 10,
          ),
          CncPunchPrimitive(
            id: 'P2',
            type: PunchType.square,
            center: CadPoint2D(150, 105),
            widthMm: 15,
            lengthMm: 15,
          ),
        ],
        dimensions: [
          CadDimension(
            id: 'dim_1',
            type: CadDimensionType.holeToEdge,
            referenceAId: 'P1',
            referenceBId: 'B1',
            pointA: CadPoint2D(50, 100),
            pointB: CadPoint2D(10, 100),
            measuredValue: 40.0,
            isDriving: true,
          ),
        ],
      );
      vm.loadDocument(doc);
    });

    test('selectPunch clears selectedDimensionId and selectConstraintId', () {
      vm.selectDimension('dim_1');
      expect(vm.selectedDimensionId, equals('dim_1'));

      vm.selectPunch('P1');
      expect(vm.selectedDimensionId, isNull);
      expect(vm.selectedConstraintId, isNull);
      expect(vm.selectedPunchId, equals('P1'));
    });

    test('selectFeature for punch clears selectedDimensionId', () {
      vm.selectDimension('dim_1');
      expect(vm.selectedDimensionId, equals('dim_1'));

      vm.selectFeature(const SheetHoleFeature(
        id: 'feat_p1',
        name: 'Hole P1',
        punchId: 'P1',
        holeType: 'round',
        x: 50,
        y: 100,
      ));
      expect(vm.selectedDimensionId, isNull);
      expect(vm.selectedPunchId, equals('P1'));
    });

    testWidgets('CadPropertyInspector displays PunchPropertySheet when punch is selected', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      vm.selectDimension('dim_1');
      expect(vm.selectedDimensionId, equals('dim_1'));

      // Select punch P1
      vm.selectPunch('P1');
      vm.setPropertyInspectorOpen(true);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 340,
              child: CadPropertyInspector(viewModel: vm),
            ),
          ),
        ),
      );

      expect(find.byType(PunchPropertySheet), findsOneWidget);
      expect(find.byType(DimensionPropertySheet), findsNothing);
    });

    test('HoleToEdge resolveAssociation projects perpendicularly onto edge segment (never midpoint)', () {
      final dim = vm.document.dimensions.first;
      final assoc = AssociativeDimensionEngine.resolveAssociation(dim, vm.document);

      // Punch is at (50, 100). Bend B1 is vertical at X=10, from Y=0 to Y=300 (midpoint is 10, 150).
      // Perpendicular projection must be at (10, 100), NOT at midpoint (10, 150)!
      expect(assoc.pA, equals(const CadPoint2D(50, 100)));
      expect(assoc.pB, equals(const CadPoint2D(10, 100)));
      expect(assoc.value, closeTo(40.0, 0.001));
    });

    test('HoleToEdge resolveLayout produces orthogonal horizontal line for vertical edge', () {
      final dim = vm.document.dimensions.first;
      final layout = AssociativeDimensionEngine.resolveLayout(dim, vm.document);

      // Dimension line must be horizontal (same Y coordinate for start and end)
      expect(layout.dimLineStart.dy, closeTo(layout.dimLineEnd.dy, 0.001));
      expect(layout.textAngle, closeTo(0.0, 0.001));
    });

    test('HoleToHole dominant X axis produces horizontal dimension', () {
      // P1 is at (50, 100), P2 is at (150, 105). dx = 100, dy = 5 -> dominant X
      const holeDim = CadDimension(
        id: 'dim_h2h',
        type: CadDimensionType.holeToHole,
        referenceAId: 'P1',
        referenceBId: 'P2',
        pointA: CadPoint2D(50, 100),
        pointB: CadPoint2D(150, 105),
        measuredValue: 100.0,
      );

      final layout = AssociativeDimensionEngine.resolveLayout(holeDim, vm.document);
      expect(layout.dimLineStart.dy, closeTo(layout.dimLineEnd.dy, 0.001));
      expect(layout.textAngle, closeTo(0.0, 0.001));
    });

    test('DirectDimensionDriver drives horizontal punch dimension purely along X axis', () {
      const hDim = CadDimension(
        id: 'dim_h_p1_p2',
        type: CadDimensionType.horizontal,
        referenceAId: 'P1',
        referenceBId: 'P2',
        pointA: CadPoint2D(50, 100),
        pointB: CadPoint2D(150, 105),
        measuredValue: 100.0,
        drivenEntityId: 'P2',
        referenceEntityId: 'P1',
      );
      vm.addDimension(hDim);

      // Drive X distance from 100 to 120
      vm.driveDimension('dim_h_p1_p2', 120.0);

      final p2 = vm.document.punches.firstWhere((p) => p.id == 'P2');
      expect(p2.center.x, closeTo(170.0, 0.01)); // 50 + 120 = 170
      expect(p2.center.y, closeTo(105.0, 0.01)); // Y coordinate strictly preserved!
    });

    test('removeDimension deletes dimension, clears selection, and supports undo', () {
      const dim = CadDimension(
        id: 'dim_to_delete',
        type: CadDimensionType.holeToHole,
        referenceAId: 'P1',
        referenceBId: 'P2',
        pointA: CadPoint2D(50, 100),
        pointB: CadPoint2D(150, 100),
        measuredValue: 100.0,
      );
      vm.addDimension(dim);
      vm.selectDimension('dim_to_delete');
      expect(vm.selectedDimensionId, equals('dim_to_delete'));
      expect(vm.document.dimensions.any((d) => d.id == 'dim_to_delete'), isTrue);

      vm.removeDimension('dim_to_delete');
      expect(vm.document.dimensions.any((d) => d.id == 'dim_to_delete'), isFalse);
      expect(vm.selectedDimensionId, isNull);

      // Undo restores it
      vm.undo();
      expect(vm.document.dimensions.any((d) => d.id == 'dim_to_delete'), isTrue);
    });

    test('removeConstraint deletes constraint, clears selection, and supports undo', () {
      const constraint = CadConstraint(
        id: 'c_to_delete',
        type: CadConstraintType.distance,
        entityIds: ['P1', 'P2'],
        parameterValue: 100.0,
      );
      vm.addConstraint(constraint);
      vm.selectConstraint('c_to_delete');
      expect(vm.selectedConstraintId, equals('c_to_delete'));
      expect(vm.document.constraints.any((c) => c.id == 'c_to_delete'), isTrue);

      vm.removeConstraint('c_to_delete');
      expect(vm.document.constraints.any((c) => c.id == 'c_to_delete'), isFalse);
      expect(vm.selectedConstraintId, isNull);

      // Undo restores it
      vm.undo();
      expect(vm.document.constraints.any((c) => c.id == 'c_to_delete'), isTrue);
    });

    test('addDimension auto-detects nearest edge when point is snapped without entityId', () {
      vm.setToolMode(StudioToolMode.addDimension);
      // Punch 1 is at (50, 100)
      vm.updateCursorMm(const CadPoint2D(50, 100));
      vm.handleCanvasClick(const CadPoint2D(50, 100));

      // Click on bottom contour edge (Y = 0) without snap entityId
      vm.updateCursorMm(const CadPoint2D(50, 0));
      vm.handleCanvasClick(const CadPoint2D(50, 0));

      expect(vm.document.dimensions.length, greaterThan(1));
      final createdDim = vm.document.dimensions.last;
      expect(createdDim.type, equals(CadDimensionType.holeToEdge));
      expect(createdDim.referenceAId, equals('P1'));
      expect(createdDim.referenceBId, isNotNull);
      expect(createdDim.referenceBId!.startsWith('CONTOUR_EDGE_'), isTrue);
    });
  });
}
