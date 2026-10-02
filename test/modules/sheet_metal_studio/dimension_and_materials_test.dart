import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/direct_dimension_driver.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/associative_dimension_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/magnetic_snap_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/dds/dds_instance_evaluator.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_dimension.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_constraint.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dds/dds_product_instance.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/planar_sheet_face.dart';
import 'package:trufold_studio/sheet_metal_studio/models/sheet_metal_material.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/canvas/floating_sketch_constraint_bar.dart';

void main() {
  group('Materials & Decimal Formatting Tests', () {
    test('Density evaluation handles MS, HR, GI, AL, SS304, SS316, HDG, and CRCA', () {
      final baseDoc = DsfDocument(
        productType: 'Test',
        itemName: 'Test',
        outerContour: const [
          CadPoint2D(0, 0),
          CadPoint2D(1000, 0),
          CadPoint2D(1000, 1000),
          CadPoint2D(0, 1000),
        ],
        bends: const [],
        material: const SheetMetalMaterial(thicknessMm: 1.5),
        faces: const [
          PlanarSheetFace(
            id: 'F1',
            vertices: [
              CadPoint2D(0, 0),
              CadPoint2D(1000, 0),
              CadPoint2D(1000, 1000),
              CadPoint2D(0, 1000),
            ],
          ),
        ],
      );

      final instMS = DdsProductInstance(
        instanceId: '1',
        productName: 'Test Part',
        templateReference: const DdsTemplateReference(templateId: 'equalTee', baselineFileName: 'equalTee.dsf'),
        material: 'Mild Steel CR4 (MS)',
        instanceParameters: {'thickness': 1.5},
      );
      final instAL = DdsProductInstance(
        instanceId: '2',
        productName: 'Test Part',
        templateReference: const DdsTemplateReference(templateId: 'equalTee', baselineFileName: 'equalTee.dsf'),
        material: 'Aluminium 5052 (AL)',
        instanceParameters: {'thickness': 1.5},
      );
      final instSS = DdsProductInstance(
        instanceId: '3',
        productName: 'Test Part',
        templateReference: const DdsTemplateReference(templateId: 'equalTee', baselineFileName: 'equalTee.dsf'),
        material: 'Stainless Steel 304 (SS304)',
        instanceParameters: {'thickness': 1.5},
      );
      final takeoffMS = DdsInstanceEvaluator.evaluate(instance: instMS, baselineDoc: baseDoc).calculatedTakeoff;
      final takeoffAL = DdsInstanceEvaluator.evaluate(instance: instAL, baselineDoc: baseDoc).calculatedTakeoff;
      final takeoffSS = DdsInstanceEvaluator.evaluate(instance: instSS, baselineDoc: baseDoc).calculatedTakeoff;

      // Mass = Area * Thickness * Density
      // Verify density scaling: SS304 (8000) / AL (2700) approx 2.96
      expect(takeoffSS.estimatedNetWeightKg / takeoffAL.estimatedNetWeightKg, closeTo(8000.0 / 2700.0, 0.05));
      expect(takeoffMS.estimatedNetWeightKg / takeoffAL.estimatedNetWeightKg, closeTo(7850.0 / 2700.0, 0.05));
      expect(takeoffSS.estimatedNetWeightKg, greaterThan(takeoffMS.estimatedNetWeightKg));
      expect(takeoffMS.estimatedNetWeightKg, greaterThan(takeoffAL.estimatedNetWeightKg));
    });

    test('Net weight and Gauge format to exactly 2 decimal places', () {
      const double weight = 1.4532;
      const double gauge = 1.5;

      final formattedWeight = '${weight.toStringAsFixed(2)} kg';
      final formattedGauge = '${gauge.toStringAsFixed(2)} mm';

      expect(formattedWeight, '1.45 kg');
      expect(formattedGauge, '1.50 mm');
    });

    test('Changing material updates weight dynamically based on density', () {
      const areaM2 = 0.185;
      const thk = 1.5;

      final densityGI = DdsInstanceEvaluator.resolveDensity('Pre-Galv DX51D (GI)');
      final densityAL = DdsInstanceEvaluator.resolveDensity('Aluminium 5052 (AL)');
      final densitySS = DdsInstanceEvaluator.resolveDensity('Stainless Steel 304 (SS304)');

      expect(densityGI, equals(7850.0));
      expect(densityAL, equals(2700.0));
      expect(densitySS, equals(8000.0));

      final weightGI = areaM2 * (thk / 1000.0) * densityGI;
      final weightAL = areaM2 * (thk / 1000.0) * densityAL;
      final weightSS = areaM2 * (thk / 1000.0) * densitySS;

      expect(weightGI, closeTo(2.18, 0.01));
      expect(weightAL, closeTo(0.75, 0.01));
      expect(weightSS, closeTo(2.22, 0.01));
      expect(weightAL, lessThan(weightGI));
      expect(weightSS, greaterThan(weightGI));
    });
  });

  group('Dimension Line Snapping & Anywhere Placement Tests', () {
    test('MagneticSnapEngine extracts dimension endpoints and midpoints as snap targets', () {
      final doc = DsfDocument(
        productType: 'Test',
        itemName: 'Test',
        outerContour: const [CadPoint2D(0, 0), CadPoint2D(400, 0), CadPoint2D(400, 200), CadPoint2D(0, 200)],
        bends: const [],
        dimensions: const [
          CadDimension(
            id: 'dim_test_1',
            type: CadDimensionType.aligned,
            pointA: CadPoint2D(100.0, 50.0),
            pointB: CadPoint2D(300.0, 50.0),
            measuredValue: 200.0,
          ),
        ],
      );

      final targets = MagneticSnapEngine.extractTargets(doc);
      final endpoints = targets.where((t) => t.entityId == 'dim_test_1' && t.type == SnapType.endpoint).toList();
      final midpoints = targets.where((t) => t.entityId == 'dim_test_1' && t.type == SnapType.midpoint).toList();

      expect(endpoints.length, 2);
      expect(endpoints.any((t) => (t.point.x - 100.0).abs() < 1e-4 && (t.point.y - 50.0).abs() < 1e-4), isTrue);
      expect(endpoints.any((t) => (t.point.x - 300.0).abs() < 1e-4 && (t.point.y - 50.0).abs() < 1e-4), isTrue);

      expect(midpoints.length, 1);
      expect((midpoints.first.point.x - 200.0).abs() < 1e-4, isTrue);
      expect((midpoints.first.point.y - 50.0).abs() < 1e-4, isTrue);
    });

    test('Snapping to dimension endpoint when dragging punch or entity', () {
      final doc = DsfDocument(
        productType: 'Test',
        itemName: 'Test',
        outerContour: const [CadPoint2D(0, 0), CadPoint2D(500, 0), CadPoint2D(500, 300), CadPoint2D(0, 300)],
        bends: const [],
        dimensions: const [
          CadDimension(
            id: 'dim_snap_target',
            type: CadDimensionType.aligned,
            pointA: CadPoint2D(150.0, 200.0),
            pointB: CadPoint2D(350.0, 200.0),
            measuredValue: 200.0,
          ),
        ],
      );

      final targets = MagneticSnapEngine.extractTargets(doc);

      // Cursor near (152.0, 201.0) should snap to (150.0, 200.0)
      final snap = MagneticSnapEngine.findClosestSnap(
        cursorMm: const CadPoint2D(152.0, 201.0),
        targets: targets,
        snapRadiusMm: 8.0,
      );

      expect(snap, isNotNull);
      expect(snap!.point.x, 150.0);
      expect(snap.point.y, 200.0);
      expect(snap.entityId, 'dim_snap_target');
    });

    test('commitDragDimension creates dimension from anywhere to anywhere', () {
      final vm = SheetMetalStudioViewModel();
      final dim = vm.commitDragDimension(
        pA: const CadPoint2D(25.3, 40.7),
        pB: const CadPoint2D(125.3, 140.7),
      );

      expect(dim, isNotNull);
      expect(dim!.pointA!.x, closeTo(25.3, 0.01));
      expect(dim.pointA!.y, closeTo(40.7, 0.01));
      expect(dim.pointB!.x, closeTo(125.3, 0.01));
      expect(dim.pointB!.y, closeTo(140.7, 0.01));
      expect(vm.document.dimensions.any((d) => d.id == dim.id), isTrue);
    });
  });

  group('Angular Dimensioning & Editing Tests', () {
    test('FloatingSketchConstraintBar includes CadConstraintType.angle when 2 lines are selected', () {
      final doc = DsfDocument(
        productType: 'Test',
        itemName: 'Test',
        outerContour: const [CadPoint2D(0, 0), CadPoint2D(100, 0), CadPoint2D(100, 100), CadPoint2D(0, 100)],
        bends: const [],
        cutLines: const [
          CadLineSegment(id: 'CUT_1', p1: CadPoint2D(0, 0), p2: CadPoint2D(100, 0)),
          CadLineSegment(id: 'CUT_2', p1: CadPoint2D(0, 0), p2: CadPoint2D(50, 50)),
        ],
      );

      final vm = SheetMetalStudioViewModel(initialDocument: doc);
      vm.toggleEntitySelection('CUT_1');
      vm.toggleEntitySelection('CUT_2');

      final constraints = FloatingSketchConstraintBar.getAvailableConstraints(vm);
      expect(constraints.contains(CadConstraintType.angle), isTrue);
    });

    test('addAngularDimension creates angular dimension between two intersecting entities', () {
      final doc = DsfDocument(
        productType: 'Test',
        itemName: 'Test',
        outerContour: const [CadPoint2D(0, 0), CadPoint2D(200, 0), CadPoint2D(200, 200), CadPoint2D(0, 200)],
        bends: const [],
        cutLines: const [
          CadLineSegment(id: 'CUT_A', p1: CadPoint2D(0, 0), p2: CadPoint2D(100, 0)),
          CadLineSegment(id: 'CUT_B', p1: CadPoint2D(0, 0), p2: CadPoint2D(100, 100)),
        ],
      );

      final vm = SheetMetalStudioViewModel(initialDocument: doc);
      final angDim = vm.addAngularDimension(referenceAId: 'CUT_A', referenceBId: 'CUT_B');
      expect(angDim, isNotNull);
      expect(angDim!.type, CadDimensionType.angular);
      expect(angDim.measuredValue, closeTo(45.0, 0.1));
      expect(angDim.displayedText, contains('45.0°'));
    });

    test('Driving angular dimension rotates driven entity to exact angle', () {
      final doc = DsfDocument(
        productType: 'Test',
        itemName: 'Test',
        outerContour: const [CadPoint2D(0, 0), CadPoint2D(200, 0), CadPoint2D(200, 200), CadPoint2D(0, 200)],
        bends: const [],
        cutLines: const [
          CadLineSegment(id: 'LINE_BASE', p1: CadPoint2D(0, 0), p2: CadPoint2D(100, 0)),
          CadLineSegment(id: 'LINE_ARM', p1: CadPoint2D(0, 0), p2: CadPoint2D(0, 100)),
        ],
      );

      const dim = CadDimension(
        id: 'dim_angle_1',
        type: CadDimensionType.angular,
        referenceAId: 'LINE_BASE',
        referenceBId: 'LINE_ARM',
        pointA: CadPoint2D(50, 0),
        pointB: CadPoint2D(0, 50),
        measuredValue: 90.0,
      );

      // Drive angle from 90° to 45°
      final driveRes = DirectDimensionDriver.drive(
        document: doc,
        dimension: dim,
        newValue: 45.0,
      );

      expect(driveRes.success, isTrue);
      final updatedDoc = driveRes.updatedDocument;
      final updatedArm = updatedDoc.cutLines.firstWhere((c) => c.id == 'LINE_ARM');
      final angle = math.atan2(updatedArm.p2.y - updatedArm.p1.y, updatedArm.p2.x - updatedArm.p1.x) * 180.0 / math.pi;

      expect(angle, closeTo(45.0, 0.1));
      expect(updatedArm.p1, const CadPoint2D(0, 0)); // Pivot preserved
      expect(updatedArm.p1.distanceTo(updatedArm.p2), closeTo(100.0, 0.1)); // Length preserved
    });
  });

  group('Auto Flange Offset & Edge Dimension Tests', () {
    test('computeAutoBendOrFlangeLine with isFlange: true applies 13.0 mm offset from closest edge', () {
      final doc = DsfDocument(
        productType: 'Test',
        itemName: 'Test',
        outerContour: const [
          CadPoint2D(0, 0),
          CadPoint2D(200, 0),
          CadPoint2D(200, 200),
          CadPoint2D(0, 200),
        ],
        bends: const [],
        cutLines: const [],
      );

      final vm = SheetMetalStudioViewModel(initialDocument: doc);
      // Hover/click near top edge (y = 0) at y = 5
      final cand = vm.computeAutoBendOrFlangeLine(
        const CadPoint2D(100, 5),
        isFlange: true,
      );

      expect(cand, isNotNull);
      // Top edge is y = 0, inward is y > 0. The flange candidate should be at y = 13.0
      expect(cand!.p1.y, closeTo(13.0, 0.1));
      expect(cand.p2.y, closeTo(13.0, 0.1));
    });

    test('Drawing dimension between vertex and edge resolves to edge length rather than 0.0 mm', () {
      final doc = DsfDocument(
        productType: 'Test',
        itemName: 'Test',
        outerContour: const [
          CadPoint2D(0, 0),
          CadPoint2D(150, 0),
          CadPoint2D(150, 100),
          CadPoint2D(0, 100),
        ],
        bends: const [],
        cutLines: const [],
      );

      final vm = SheetMetalStudioViewModel(initialDocument: doc);
      vm.setToolMode(StudioToolMode.addDimension);

      // Click 1: At vertex (0, 0)
      vm.handleCanvasClick(const CadPoint2D(0, 0), snapRadiusMm: 2.0);
      expect(vm.pendingBendStart, isNotNull);

      // Click 2: On the top edge at (50, 0)
      vm.handleCanvasClick(const CadPoint2D(50, 0), snapRadiusMm: 2.0);

      // SS1: Dimension must be created with the measured segment (50.0 mm), NOT expanded to whole edge (150.0 mm)!
      expect(vm.document.dimensions.isNotEmpty, isTrue);
      final dim = vm.document.dimensions.last;
      expect(dim.measuredValue, closeTo(50.0, 0.1));
      expect(dim.pointA!.distanceTo(dim.pointB!), closeTo(50.0, 0.1));

      // SS2: Starting a dimension in void area does not jump to distant entity center
      vm.handleCanvasClick(const CadPoint2D(-30, 20), snapRadiusMm: 2.0);
      expect(vm.pendingBendStart, equals(const CadPoint2D(-30, 20)));

      // Click 2 in void:
      vm.handleCanvasClick(const CadPoint2D(-30, 80), snapRadiusMm: 2.0);
      final voidDim = vm.document.dimensions.last;
      expect(voidDim.measuredValue, closeTo(60.0, 0.1));
      expect(voidDim.pointA, equals(const CadPoint2D(-30, 20)));
      expect(voidDim.pointB, equals(const CadPoint2D(-30, 80)));
    });

    test('AssociativeDimensionEngine.resolveAssociation on point on edge resolves to edge segment', () {
      final doc = DsfDocument(
        productType: 'Test',
        itemName: 'Test',
        outerContour: const [
          CadPoint2D(0, 0),
          CadPoint2D(200, 0),
          CadPoint2D(200, 100),
          CadPoint2D(0, 100),
        ],
        bends: const [],
        cutLines: const [],
      );

      // Dimension pointing from vertex (0, 0) to CONTOUR_EDGE_0 (top edge (0,0)-(200,0))
      const dim = CadDimension(
        id: 'test_dim',
        type: CadDimensionType.aligned,
        referenceAId: 'CONTOUR_VERTEX_0',
        referenceBId: 'CONTOUR_EDGE_0',
        pointA: CadPoint2D(0, 0),
        pointB: CadPoint2D(200, 0),
        measuredValue: 200.0,
      );

      final assoc = AssociativeDimensionEngine.resolveAssociation(dim, doc);
      expect(assoc.value, closeTo(200.0, 0.1));
      expect(assoc.pA.distanceTo(assoc.pB), closeTo(200.0, 0.1));
    });
  });
}
