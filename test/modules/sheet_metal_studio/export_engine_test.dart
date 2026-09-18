// =============================================================================
// export_engine_test.dart
//
// Unit tests for CAD/CAM Export Engines:
// 1. Wavefront OBJ (.obj) 3D mesh export (surface and solid thickness)
// 2. Stereolithography STL (.stl) export
// 3. Pure-Dart standard AutoCAD DXF (.dxf) export
// 4. Danish Datasheet (.dds) and Danish Sheet Fold (.dsf) package export
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dds_package.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/export_engine_3d.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/dxf_exporter.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cnc_turret_engine.dart';

void main() {
  group('CAD/CAM Export Engine Suite Tests', () {
    late DsfDocument doc;

    setUp(() {
      doc = DsfDocument.sampleCableTray(
        width: 100.0,
        height: 50.0,
        length: 3000.0,
        flange: 15.0,
        thickness: 1.5,
      );

      // Add a couple punches
      final punch1 = CncTurretEngine.createRoundHole(
        id: 'H1',
        center: const CadPoint2D(115.0, 500.0),
        diameterMm: 8.0,
      );
      final punch2 = CncTurretEngine.createObroundSlot(
        id: 'S1',
        center: const CadPoint2D(115.0, 1000.0),
        widthMm: 7.0,
        lengthMm: 25.0,
      );
      doc = doc.copyWith(punches: [punch1, punch2]);
    });

    test('1. Wavefront OBJ export (mid-surface & solid thickness)', () {
      final foldedMesh = KinematicFoldEngine.computeFold(doc: doc, foldProgress: 1.0);
      expect(foldedMesh.isNotEmpty, isTrue);

      // 1A. Mid-surface OBJ export (thickness = 0)
      final midSurfaceObj = ExportEngine3d.exportWavefrontObj(
        polygons: foldedMesh,
        thicknessMm: 0.0,
        partName: 'CableTray100x50',
      );

      expect(midSurfaceObj.contains('o CableTray100x50'), isTrue);
      expect(midSurfaceObj.contains('v '), isTrue);
      expect(midSurfaceObj.contains('vn '), isTrue);
      expect(midSurfaceObj.contains('f '), isTrue);
      expect(midSurfaceObj.contains('Mid-surface'), isTrue);

      // 1B. Extruded Solid body OBJ export (thickness = 1.5mm)
      final solidObj = ExportEngine3d.exportWavefrontObj(
        polygons: foldedMesh,
        thicknessMm: 1.5,
        partName: 'CableTraySolid',
      );

      expect(solidObj.contains('Solid Thickness: 1.5mm'), isTrue);
      // Solid extrusion doubles vertices (top + bottom) and adds side normals
      final midVCount = RegExp(r'^v ', multiLine: true).allMatches(midSurfaceObj).length;
      final solidVCount = RegExp(r'^v ', multiLine: true).allMatches(solidObj).length;
      expect(solidVCount, equals(midVCount * 2));
    });

    test('2. ASCII STL 3D mesh export', () {
      final foldedMesh = KinematicFoldEngine.computeFold(doc: doc, foldProgress: 1.0);
      final stl = ExportEngine3d.exportAsciiStl(
        polygons: foldedMesh,
        thicknessMm: 1.5,
        solidName: 'CableTray_100x50',
      );

      expect(stl.startsWith('solid CableTray_100x50'), isTrue);
      expect(stl.contains('facet normal'), isTrue);
      expect(stl.contains('outer loop'), isTrue);
      expect(stl.contains('vertex '), isTrue);
      expect(stl.contains('endloop'), isTrue);
      expect(stl.contains('endfacet'), isTrue);
      expect(stl.trim().endsWith('endsolid CableTray_100x50'), isTrue);
    });

    test('3. Pure-Dart AutoCAD DXF export with CNC layers', () {
      final dxf = DxfExporter.exportDxf(doc);

      // Header verification
      expect(dxf.contains('\$ACADVER'), isTrue);
      expect(dxf.contains('AC1009'), isTrue);

      // Layer table verification
      expect(dxf.contains('CUT'), isTrue);
      expect(dxf.contains('BEND_UP'), isTrue);
      expect(dxf.contains('BEND_DOWN'), isTrue);
      expect(dxf.contains('HOLES'), isTrue);
      expect(dxf.contains('ANNOTATION'), isTrue);

      // Entities verification
      expect(dxf.contains('POLYLINE'), isTrue);
      expect(dxf.contains('LINE'), isTrue);
      expect(dxf.contains('CIRCLE'), isTrue); // Punch H1
      expect(dxf.contains('UP 90.0°'), isTrue); // Bend annotation text
      expect(dxf.contains('truFold Studio by Danish'), isTrue);
      expect(dxf.trim().endsWith('EOF'), isTrue);
    });

    test('4. Danish Datasheet (.dds) package bundle creation and parsing', () {
      final pkg = DdsPackage.create(
        document: doc,
        projectName: 'Lusail Commercial Tower',
        customerName: 'Danish Electrical Industries',
        drawingNumber: 'DSF-LT-001',
        foldProgress: 1.0,
      );

      expect(pkg.format, equals('Danish Datasheet (.dds)'));
      expect(pkg.metadata['projectName'], equals('Lusail Commercial Tower'));
      expect(pkg.metadata['customerName'], equals('Danish Electrical Industries'));
      expect(pkg.pressBrakeSequence.length, equals(doc.bends.length));

      // Test JSON round-trip
      final jsonString = pkg.toJsonString(pretty: true);
      expect(jsonString.contains('Danish Datasheet (.dds)'), isTrue);

      final decoded = DdsPackage.fromJson(pkg.toJson());
      expect(decoded.document.partNumber, equals(doc.partNumber));
      expect(decoded.document.bends.length, equals(doc.bends.length));
      expect(decoded.document.punches.length, equals(2));
      expect(decoded.pressBrakeSequence.first['targetAngleDeg'], equals(45.0));
    });

    test('5. Native .dsf JSON serialization export', () {
      final jsonStr = doc.toJsonString();
      expect(jsonStr.contains('DANISH_SHEET_FOLD'), isTrue);
      expect(jsonStr.contains('F_FLOOR'), isTrue);

      final restored = DsfDocument.fromJsonString(jsonStr);
      expect(restored.bends.length, equals(doc.bends.length));
      expect(restored.outerContour.length, equals(doc.outerContour.length));
      expect(restored.punches.length, equals(doc.punches.length));
    });
  });
}
