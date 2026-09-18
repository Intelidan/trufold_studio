// =============================================================================
// scaled_template_and_dxf_test.dart
//
// Comprehensive test suite for:
// 1. Parametric Scaled Template Workings (Tee, Bend 90°, Reducer).
// 2. DXF Export Cleanliness & Geometry Integrity (ARC 51 end angle, SEQEND layer,
//    titleblock positioning below part bounds, dimension layer export).
// 3. DXF Mini Parser round-trip ingestion of exported standard DXF.
// 4. Interactive Dimension click-and-drag tool, Alt free movement, & persistence.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_dimension.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/sheet_metal_material.dart';
import 'package:trufold_studio/sheet_metal_studio/models/template_parameter_definition.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/topological_zone_morpher.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/dxf_exporter.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/dxf_mini_parser.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';

void main() {
  group('1. Scaled Template Workings & Morphing Tests', () {
    test('Cable Tray Tee scales parametrically from 100mm to 200mm width', () {
      final template = TemplateParameterDefinition.cableTrayTee();
      final baseline = TopologicalZoneMorpher.createBaselineForTemplate(template);

      expect(baseline.outerContour.isNotEmpty, isTrue);
      final initialWidth = baseline.blankWidthMm;

      // Morph width from 100 to 200mm, branchWidth to 150mm
      final morphed = TopologicalZoneMorpher.morph(
        baselineDocument: baseline,
        template: template,
        targetParameters: {'width': 200.0, 'branchWidth': 150.0, 'height': 50.0},
      );

      expect(morphed.outerContour.isNotEmpty, isTrue);
      expect(morphed.blankWidthMm, greaterThan(initialWidth));
      expect(morphed.bends.length, equals(baseline.bends.length));
      expect(morphed.punches.length, equals(baseline.punches.length));
      expect(morphed.faces.isNotEmpty, isTrue);
    });

    test('Cable Tray 90° Bend scales radius and arm width', () {
      final template = TemplateParameterDefinition.cableTrayBend90();
      final baseline = TopologicalZoneMorpher.createBaselineForTemplate(template);

      final morphed = TopologicalZoneMorpher.morph(
        baselineDocument: baseline,
        template: template,
        targetParameters: {'width': 150.0, 'height': 75.0, 'radius': 150.0},
      );

      expect(morphed.blankWidthMm, greaterThan(baseline.blankWidthMm));
      expect(morphed.blankLengthMm, greaterThan(baseline.blankLengthMm));
      expect(morphed.bends.length, equals(baseline.bends.length));
    });

    test('Cable Tray Reducer scales with negative Y coordinates safely', () {
      final template = TemplateParameterDefinition.cableTrayReducer();
      final baseline = TopologicalZoneMorpher.createBaselineForTemplate(template);

      final morphed = TopologicalZoneMorpher.morph(
        baselineDocument: baseline,
        template: template,
        targetParameters: {'widthIn': 200.0, 'widthOut': 100.0, 'height': 50.0, 'length': 250.0},
      );

      expect(morphed.outerContour.length, greaterThanOrEqualTo(4));
      // Verify reducer has negative Y bounds
      final hasNegativeY = morphed.outerContour.any((p) => p.y < 0);
      expect(hasNegativeY, isTrue);
    });
  });

  group('2. Clean DXF Export Algorithm Tests', () {
    test('Arc entities export endAngleDeg using group code 51 (never group 60)', () {
      final doc = DsfDocument(
        productType: 'Arc Test Bracket',
        itemName: 'ARC-01',
        outerContour: const [
          CadPoint2D(0, 0),
          CadPoint2D(100, 0),
          CadPoint2D(100, 50),
          CadPoint2D(0, 50),
        ],
        bends: const [],
        arcs: [
          CadArc2D(
            id: 'ARC_1',
            center: const CadPoint2D(50, 25),
            radius: 15.0,
            startAngleDeg: 0.0,
            endAngleDeg: 180.0,
            layer: 'CUT',
          ),
        ],
      );

      final dxf = DxfExporter.exportDxf(doc);

      // Verify ARC section format
      expect(dxf.contains('0\nARC'), isTrue);
      expect(dxf.contains('50\n0.0'), isTrue);
      // Crucial: group code 51 must be used for end angle
      expect(dxf.contains('51\n180.0'), isTrue);
      // Group code 60 must NOT be used for end angle
      expect(dxf.contains('60\n180.0'), isFalse);
    });

    test('Polyline entities include layer 8 on SEQEND entity', () {
      final doc = DsfDocument(
        productType: 'Polyline Bracket',
        itemName: 'POLY-01',
        outerContour: const [
          CadPoint2D(0, 0),
          CadPoint2D(80, 0),
          CadPoint2D(80, 40),
          CadPoint2D(0, 40),
        ],
        outerContourLayer: 'CUT',
        bends: const [],
      );

      final dxf = DxfExporter.exportDxf(doc);

      // SEQEND must be followed by layer 8
      expect(dxf.contains('0\nSEQEND\n8\nCUT'), isTrue);
    });

    test('Titleblock metadata text is strictly positioned below part minimum Y', () {
      // Create a part that spans negative Y coordinates (like a Reducer or centered bracket)
      final doc = DsfDocument(
        productType: 'Reducer Bracket',
        itemName: 'RED-01',
        outerContour: const [
          CadPoint2D(0, -100.0),
          CadPoint2D(150, -60.0),
          CadPoint2D(150, 60.0),
          CadPoint2D(0, 100.0),
        ],
        bends: const [],
      );

      final dxf = DxfExporter.exportDxf(doc);

      // The part's minimum Y is -100.0.
      // The titleblock text must be positioned below -100.0 (e.g. -115.0), NOT at -25.0
      expect(dxf.contains('20\n-25.0'), isFalse, reason: 'Titleblock must not overlap part geometry at -25.0');
      expect(dxf.contains('20\n-115.0'), isTrue, reason: 'Titleblock must be positioned below part minY (-100 - 15 = -115)');
    });

    test('Dimensions are exported cleanly to layer ANNOTATION', () {
      final doc = DsfDocument(
        productType: 'Dimensioned Bracket',
        itemName: 'DIM-01',
        outerContour: const [
          CadPoint2D(0, 0),
          CadPoint2D(100, 0),
          CadPoint2D(100, 50),
          CadPoint2D(0, 50),
        ],
        bends: const [],
        dimensions: const [
          CadDimension(
            id: 'dim_1',
            type: CadDimensionType.aligned,
            pointA: CadPoint2D(0, 0),
            pointB: CadPoint2D(100, 0),
            measuredValue: 100.0,
            dimensionLineOffset: 15.0,
          ),
        ],
      );

      final dxf = DxfExporter.exportDxf(doc);

      expect(dxf.contains('8\nANNOTATION'), isTrue);
      expect(dxf.contains('1\n100.00'), isTrue);
    });

    test('DxfMiniParser round-trip parses exported POLYLINE and ARC entities', () {
      final doc = DsfDocument(
        productType: 'Morphed Bracket',
        itemName: 'MB-01',
        material: const SheetMetalMaterial(thicknessMm: 2.0),
        outerContour: const [
          CadPoint2D(0, 0),
          CadPoint2D(120, 0),
          CadPoint2D(120, 60),
          CadPoint2D(0, 60),
        ],
        bends: const [],
        arcs: [
          CadArc2D(
            id: 'A1',
            center: const CadPoint2D(60, 30),
            radius: 12.0,
            startAngleDeg: 0.0,
            endAngleDeg: 90.0,
            layer: 'CUT',
          ),
        ],
      );

      final exportedDxf = DxfExporter.exportDxf(doc);
      final parsed = DxfMiniParser.parse(exportedDxf);

      // Verify DxfMiniParser successfully ingested entities
      final polylines = parsed.getEntitiesOfType<DxfRawPolyline>();
      final arcs = parsed.getEntitiesOfType<DxfRawArc>();

      expect(polylines.isNotEmpty, isTrue, reason: 'DxfMiniParser must parse POLYLINE entity');
      expect(polylines.first.vertices.length, equals(4));
      expect(arcs.isNotEmpty, isTrue, reason: 'DxfMiniParser must parse ARC entity');
      expect(arcs.first.endAngleDeg, equals(90.0), reason: 'Arc end angle must be 90.0 from group 51');
    });
  });

  group('3. Interactive Dimension Drag Tool & Alt Free Movement Tests', () {
    test('commitDragDimension creates persistent dimension in document', () {
      final vm = SheetMetalStudioViewModel();

      final initialDimCount = vm.document.dimensions.length;
      final dim = vm.commitDragDimension(
        pA: const CadPoint2D(10.0, 10.0),
        pB: const CadPoint2D(110.0, 10.0),
        offset: 25.0,
      );

      expect(dim, isNotNull);
      expect(vm.document.dimensions.length, equals(initialDimCount + 1));
      expect(dim!.measuredValue, closeTo(100.0, 0.01));
      expect(vm.selectedDimensionId, equals(dim.id));

      // Test dimension deletion via deleteSelectedEntities()
      vm.deleteSelectedEntities();
      expect(vm.document.dimensions.where((d) => d.id == dim.id), isEmpty);
    });

    test('isAltPressed completely bypasses snapping in resolveEffectivePoint', () {
      final vm = SheetMetalStudioViewModel();

      // Load a document with clear geometry
      vm.loadTemplate(TemplateParameterDefinition.cableTrayTee());

      // Nearby point close to an edge vertex
      final nearVertex = const CadPoint2D(0.5, 0.5);

      // Without Alt: snaps to origin / vertex (0, 0)
      vm.isAltPressed = false;
      final snapped = vm.resolveEffectivePoint(nearVertex, snapRadiusMm: 8.0);
      expect(snapped.x == 0.0 && snapped.y == 0.0, isTrue);

      // With Alt: moves freely, returns exact nearVertex coordinates
      vm.isAltPressed = true;
      final free = vm.resolveEffectivePoint(nearVertex, snapRadiusMm: 8.0);
      expect(free.x, equals(0.5));
      expect(free.y, equals(0.5));
    });
  });
}
