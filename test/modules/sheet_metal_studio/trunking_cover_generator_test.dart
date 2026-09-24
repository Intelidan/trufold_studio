// =============================================================================
// trunking_cover_generator_test.dart
//
// Comprehensive Unit & Geometric Verification Tests for Trunking Accessory Covers
// Tests:
// 1. Equal Tee Cover (Main face, 3 side flanges, central punch, open ports)
// 2. Unequal Tee Cover with Hbody - Hport Extended 90° Drop Flaps
// 3. Equal Cross Cover (Main face, 4 corner cheek flanges, open ports)
// 4. Unequal Cross Cover with Hbody - Hport Extended 90° Drop Flaps
// 5. 45° Bend Cover (Inner and outer flanges, open ports)
// 6. DSF Round-trip Serialization with Cover (backward compatible, full restoration)
// 7. Non-destructive Base Part Guarantee (base geometry unaffected by cover)
// =============================================================================

import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/trunking_cover_data.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/covers/trunking_cover_generator.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/dxf_exporter.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/models/fold_bend_line.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';

void main() {
  group('TrunkingCoverGenerator Unit & Manufacturing Geometry Tests', () {
    test('Test 1 — Equal Tee Cover Generation (3 flanges, open ports, central mounting hole)', () {
      final teeFile = File('assets/dxf_templates/trunking_accessories/equal_tee_100x100.dsf');
      final json = jsonDecode(teeFile.readAsStringSync()) as Map<String, dynamic>;
      final baseDoc = DsfDocument.fromJson(json);

      final coverData = TrunkingCoverGenerator.generateCover(baseDoc);
      expect(coverData, isNotNull);
      final coverDoc = coverData!.document;

      // 1. Base Part Unchanged
      expect(baseDoc.faces.length, equals(11));
      expect(baseDoc.bends.length, equals(10));

      // 2. Cover Has Main Top Face and 3 Side Flanges
      expect(coverDoc.baseFaceId, equals('COVER_MAIN_FACE'));
      final mainFace = coverDoc.faces.firstWhere((f) => f.id == 'COVER_MAIN_FACE');
      expect(mainFace.vertices.length, equals(6)); // Hexagonal Equal Tee floor footprint

      // Exactly 3 side flanges (2 for 45° corner cheeks, 1 for bottom main run wall)
      final flangeFaces = coverDoc.faces.where((f) => f.id.startsWith('CF_')).toList();
      expect(flangeFaces.length, equals(3));

      // Exactly 3 90° fold bends
      expect(coverDoc.bends.length, equals(3));
      for (final b in coverDoc.bends) {
        expect(b.targetAngleDeg, equals(90.0));
      }

      // Central mounting punch
      expect(coverDoc.punches.length, equals(1));
      expect(coverDoc.punches.first.id, equals('COVER_MOUNT_HOLE'));
      expect(coverDoc.punches.first.diameterMm, equals(6.0));

      // Default beside-base placement offset
      expect(coverData.offset2D.x, greaterThan(150.0));
      expect(coverData.isVisible2D, isTrue);
      expect(coverData.isVisible3D, isTrue);
    });

    test('Test 2 — Unequal Tee Cover with Hbody - Hport Extended 90° Drop Flaps', () {
      final teeFile = File('assets/dxf_templates/trunking_accessories/equal_tee_100x100.dsf');
      final json = jsonDecode(teeFile.readAsStringSync()) as Map<String, dynamic>;
      final baseDoc = DsfDocument.fromJson(json).copyWith(
        productType: 'Cable Trunking Unequal Tee',
        itemName: 'Unequal Tee 100x100x50x100x100x50x50',
      );

      // User Scenario:
      // Port 1 = 100mm, Port 2 = 50mm, Port 3 = 75mm
      // Body Height = max(100, 50, 75) = 100mm
      // Port 1 Drop Flap = 100 - 100 = 0mm (no flap, open mouth)
      // Port 2 Drop Flap = 100 - 50 = 50mm (50mm extended 90° flap)
      // Port 3 Drop Flap = 100 - 75 = 25mm (25mm extended 90° flap)
      final coverData = TrunkingCoverGenerator.generateCover(
        baseDoc,
        parameterOverrides: {
          'port1_height': 100.0,
          'port2_height': 50.0,
          'port3_height': 75.0,
        },
      );

      expect(coverData, isNotNull);
      final coverDoc = coverData!.document;

      // Drop flaps for Port 2 and Port 3
      final dropFlaps = coverDoc.faces.where((f) => f.id.startsWith('C_DROP_F_')).toList();
      expect(dropFlaps.length, equals(2));

      // Find drop flap for Port 2 (height 50mm, flap length = 50mm)
      final flapPort2 = dropFlaps.firstWhere((f) => f.label.contains('Port 2'));
      expect(flapPort2.label, contains('50.0mm'));

      // Find drop flap for Port 3 (height 75mm, flap length = 25mm)
      final flapPort3 = dropFlaps.firstWhere((f) => f.label.contains('Port 3'));
      expect(flapPort3.label, contains('25.0mm'));

      // Bends count: 3 side flanges + 2 drop flaps = 5 bends total!
      expect(coverDoc.bends.length, equals(5));
      for (final b in coverDoc.bends) {
        expect(b.targetAngleDeg, equals(90.0));
      }
    });

    test('Test 3 — Equal Cross Cover Generation (4 corner cheek flanges at 45°, 4 open ports)', () {
      final crossFile = File('assets/dxf_templates/trunking_accessories/equal_cross_100x100.dsf');
      final json = jsonDecode(crossFile.readAsStringSync()) as Map<String, dynamic>;
      final baseDoc = DsfDocument.fromJson(json);

      final coverData = TrunkingCoverGenerator.generateCover(baseDoc);
      expect(coverData, isNotNull);
      final coverDoc = coverData!.document;

      // Main face matches octagonal floor
      final mainFace = coverDoc.faces.firstWhere((f) => f.id == 'COVER_MAIN_FACE');
      expect(mainFace.vertices.length, equals(8));

      // Exactly 4 corner cheek flanges (1 per 45° corner cheek)
      final flangeFaces = coverDoc.faces.where((f) => f.id.startsWith('CF_')).toList();
      expect(flangeFaces.length, equals(4));

      // Exactly 4 bends
      expect(coverDoc.bends.length, equals(4));

      // Central mounting hole
      expect(coverDoc.punches.length, equals(1));
      expect(coverDoc.punches.first.id, equals('COVER_MOUNT_HOLE'));
    });

    test('Test 4 — Unequal Cross Cover with Hbody - Hport Extended 90° Drop Flaps', () {
      final crossFile = File('assets/dxf_templates/trunking_accessories/equal_cross_100x100.dsf');
      final json = jsonDecode(crossFile.readAsStringSync()) as Map<String, dynamic>;
      final baseDoc = DsfDocument.fromJson(json).copyWith(
        productType: 'Cable Trunking Unequal Cross',
        itemName: 'Unequal Cross 100x50x100x50',
      );

      // Scenario:
      // Port 1 (North) = 100mm -> Hbody = 100mm -> Drop = 0mm (open)
      // Port 2 (East) = 50mm -> Drop = 50mm
      // Port 3 (West) = 100mm -> Drop = 0mm (open)
      // Port 4 (South) = 50mm -> Drop = 50mm
      final coverData = TrunkingCoverGenerator.generateCover(
        baseDoc,
        parameterOverrides: {
          'port1_height': 100.0,
          'port2_height': 50.0,
          'port3_height': 100.0,
          'port4_height': 50.0,
        },
      );

      expect(coverData, isNotNull);
      final coverDoc = coverData!.document;

      // Exactly 2 drop flaps (Ports 2 and 4)
      final dropFlaps = coverDoc.faces.where((f) => f.id.startsWith('C_DROP_F_')).toList();
      expect(dropFlaps.length, equals(2));
      for (final flap in dropFlaps) {
        expect(flap.label, contains('50.0mm'));
      }

      // Total bends: 4 corner cheek flanges + 2 drop flaps = 6 bends
      expect(coverDoc.bends.length, equals(6));
    });

    test('Test 5 — 45° Bend Cover Generation (inner and outer cheek flanges)', () {
      final bendFile = File('assets/dxf_templates/trunking_accessories/45_deg_bend_100x100.dsf');
      final json = jsonDecode(bendFile.readAsStringSync()) as Map<String, dynamic>;
      final baseDoc = DsfDocument.fromJson(json);

      final coverData = TrunkingCoverGenerator.generateCover(baseDoc);
      expect(coverData, isNotNull);
      final coverDoc = coverData!.document;

      // Main face matches bend floor
      final mainFace = coverDoc.faces.firstWhere((f) => f.id == 'COVER_MAIN_FACE');
      expect(mainFace.vertices.length, equals(5));

      // 2 side cheek flanges (inner cheek and outer cheek)
      final flangeFaces = coverDoc.faces.where((f) => f.id.startsWith('CF_')).toList();
      expect(flangeFaces.length, greaterThanOrEqualTo(2));

      // Central mounting punch
      expect(coverDoc.punches.length, equals(1));
    });

    test('Test 6 — DSF Round-trip Serialization with Cover (Backward Compatible)', () {
      final teeFile = File('assets/dxf_templates/trunking_accessories/equal_tee_100x100.dsf');
      final json = jsonDecode(teeFile.readAsStringSync()) as Map<String, dynamic>;
      final baseDoc = DsfDocument.fromJson(json);

      // 1. Legacy DSF has no cover initially
      expect(baseDoc.cover, isNull);

      // 2. Attach generated cover
      final coverData = TrunkingCoverGenerator.generateCover(baseDoc);
      final docWithCover = baseDoc.copyWith(cover: coverData);
      expect(docWithCover.cover, isNotNull);

      // 3. Serialize to JSON string
      final jsonString = docWithCover.toJsonString(pretty: true);
      expect(jsonString, contains('"cover":'));
      expect(jsonString, contains('"COVER_MAIN_FACE"'));

      // 4. Parse back from JSON string
      final reopenedDoc = DsfDocument.parseJsonString(jsonString);
      expect(reopenedDoc.cover, isNotNull);
      expect(reopenedDoc.cover!.isVisible2D, isTrue);
      expect(reopenedDoc.cover!.isVisible3D, isTrue);
      expect(reopenedDoc.cover!.placementMode2D, equals(CoverPlacementMode2D.besideBase));
      expect(reopenedDoc.cover!.offset2D.x, closeTo(coverData!.offset2D.x, 0.01));
      expect(reopenedDoc.cover!.document.faces.length, equals(coverData.document.faces.length));
      expect(reopenedDoc.cover!.document.bends.length, equals(coverData.document.bends.length));

      // 5. Base part remains 100% identical
      expect(reopenedDoc.outerContour.length, equals(baseDoc.outerContour.length));
      expect(reopenedDoc.bends.length, equals(baseDoc.bends.length));
      expect(reopenedDoc.faces.length, equals(baseDoc.faces.length));
    });

    test('Test 7 — DXF Export Base Only Scope', () {
      final teeFile = File('assets/dxf_templates/trunking_accessories/equal_tee_100x100.dsf');
      final json = jsonDecode(teeFile.readAsStringSync()) as Map<String, dynamic>;
      final baseDoc = DsfDocument.fromJson(json);
      final coverData = TrunkingCoverGenerator.generateCover(baseDoc);
      final docWithCover = baseDoc.copyWith(cover: coverData);

      final dxfBaseOnly = DxfExporter.exportBaseAndCoverDxf(docWithCover, scope: DxfExportScope.baseOnly);
      expect(dxfBaseOnly, contains('SECTION'));
      expect(dxfBaseOnly, contains('ENTITIES'));
      expect(dxfBaseOnly, contains('PART:'));
      expect(dxfBaseOnly, contains('BASE'));
      expect(dxfBaseOnly, isNot(contains('COVER_MOUNT_HOLE')));
    });

    test('Test 8 — DXF Export Cover Only Scope', () {
      final teeFile = File('assets/dxf_templates/trunking_accessories/equal_tee_100x100.dsf');
      final json = jsonDecode(teeFile.readAsStringSync()) as Map<String, dynamic>;
      final baseDoc = DsfDocument.fromJson(json);
      final coverData = TrunkingCoverGenerator.generateCover(baseDoc);
      final docWithCover = baseDoc.copyWith(cover: coverData);

      final dxfCoverOnly = DxfExporter.exportBaseAndCoverDxf(docWithCover, scope: DxfExportScope.coverOnly);
      expect(dxfCoverOnly, contains('SECTION'));
      expect(dxfCoverOnly, contains('ENTITIES'));
      expect(dxfCoverOnly, contains('COVER'));
      // Contains the cover's 90° down-folding side flanges and central mount hole
      expect(dxfCoverOnly, contains('DN 90.0°'));
    });

    test('Test 9 — DXF Export Both Base and Cover Side-by-Side Scope', () {
      final teeFile = File('assets/dxf_templates/trunking_accessories/equal_tee_100x100.dsf');
      final json = jsonDecode(teeFile.readAsStringSync()) as Map<String, dynamic>;
      final baseDoc = DsfDocument.fromJson(json);
      final coverData = TrunkingCoverGenerator.generateCover(baseDoc);
      final docWithCover = baseDoc.copyWith(cover: coverData);

      final dxfCombined = DxfExporter.exportBaseAndCoverDxf(docWithCover, scope: DxfExportScope.bothSideBySide);
      expect(dxfCombined, contains('SECTION'));
      expect(dxfCombined, contains('ENTITIES'));
      expect(dxfCombined, contains('BASE'));
      expect(dxfCombined, contains('COVER'));
      // Contains both parts' bends: UP from base and DN from cover
      expect(dxfCombined, contains('UP 90.0°'));
      expect(dxfCombined, contains('DN 90.0°'));
    });

    test('Test 10 — Beside-Base Offset Guarantees Positive Clearance Gap', () {
      final teeFile = File('assets/dxf_templates/trunking_accessories/equal_tee_100x100.dsf');
      final json = jsonDecode(teeFile.readAsStringSync()) as Map<String, dynamic>;
      final baseDoc = DsfDocument.fromJson(json);
      final coverData = TrunkingCoverGenerator.generateCover(baseDoc);

      expect(coverData, isNotNull);
      final baseBbox = TrunkingCoverGenerator.calculateDocumentBbox(baseDoc);
      final coverBbox = TrunkingCoverGenerator.calculateDocumentBbox(coverData!.document);

      final placedCoverMinX = coverBbox.minX + coverData.offset2D.x;
      final gap = placedCoverMinX - baseBbox.maxX;

      // The clearance gap between rightmost base point and leftmost cover point must be >= 50mm
      expect(gap, greaterThanOrEqualTo(50.0));
    });

    test('Test 11 — Direct Unequal Tee Template Cover Generation (Port 2 Drop Flap)', () {
      final file = File('assets/dxf_templates/trunking_accessories/unequal_tee_100x100x50x100x100x50x50.dsf');
      final baseDoc = DsfDocument.fromJson(jsonDecode(file.readAsStringSync()));

      final coverData = TrunkingCoverGenerator.generateCover(baseDoc);
      expect(coverData, isNotNull);
      final coverDoc = coverData!.document;

      // 1. Verify face composition: Main ceiling + side flanges + Port 2 drop flap
      final faceIds = coverDoc.faces.map((f) => f.id).toSet();
      expect(faceIds, contains('COVER_MAIN_FACE'));
      expect(faceIds, contains('C_DROP_F_1'));

      // 2. Verify Port 2 mouth bend line
      final dropBend = coverDoc.bends.firstWhere((b) => b.id == 'C_DROP_B_1');
      expect((dropBend.p1.x - 215.29).abs(), lessThan(0.1));
      expect((dropBend.p2.x - 215.29).abs(), lessThan(0.1));
      expect(dropBend.targetAngleDeg, equals(90.0));
      expect(dropBend.direction, equals(BendDirection.down));

      // 3. Verify 2D flap extends outward by 50mm
      final flapFace = coverDoc.faces.firstWhere((f) => f.id == 'C_DROP_F_1');
      final maxX = flapFace.vertices.map((v) => v.x).reduce(math.max);
      expect((maxX - 265.29).abs(), lessThan(0.1));

      // 4. Verify 3D folding: drops 50mm downward along negative Z
      final coverFolded = KinematicFoldEngine.computeFold(doc: coverDoc, foldProgress: 1.0);
      final flapPoly = coverFolded.firstWhere((p) => p.faceId == 'C_DROP_F_1');
      final minZ = flapPoly.vertices.map((v) => v.z).reduce(math.min);
      final maxZ = flapPoly.vertices.map((v) => v.z).reduce(math.max);
      expect((maxZ - minZ - 50.0).abs(), lessThan(1.0));

      // 5. Verify open mouths: only 1 drop flap generated (Ports 1 and 3 are 100mm, hence open)
      final dropFaces = coverDoc.faces.where((f) => f.id.startsWith('C_DROP_F_')).toList();
      expect(dropFaces.length, equals(1));
    });

    test('Test 12 — Direct Unequal Cross Template Cover Generation (Ports 1 & 3 Drop Flaps)', () {
      final file = File('assets/dxf_templates/trunking_accessories/unequal_cross_100x50x100x50.dsf');
      final baseDoc = DsfDocument.fromJson(jsonDecode(file.readAsStringSync()));

      final coverData = TrunkingCoverGenerator.generateCover(baseDoc);
      expect(coverData, isNotNull);
      final coverDoc = coverData!.document;

      // In Unequal Cross (100x50x100x50), Ports 1 & 3 have 50mm height, while Ports 2 & 4 have 100mm height
      // The cover should generate two 50mm drop flaps for Ports 1 & 3
      final dropFaces = coverDoc.faces.where((f) => f.id.startsWith('C_DROP_F_')).toList();
      expect(dropFaces.length, equals(2));

      for (final flap in dropFaces) {
        final flapPoly = KinematicFoldEngine.computeFold(doc: coverDoc, foldProgress: 1.0)
            .firstWhere((p) => p.faceId == flap.id);
        final minZ = flapPoly.vertices.map((v) => v.z).reduce(math.min);
        final maxZ = flapPoly.vertices.map((v) => v.z).reduce(math.max);
        expect((maxZ - minZ - 50.0).abs(), lessThan(1.0));
      }
    });

    test('Test 13 — Real-time 3D Cover Scaling during CMS Teach Scaling', () {
      final file = File('assets/dxf_templates/trunking_accessories/unequal_tee_100x100x50x100x100x50x50.dsf');
      final baseDoc = DsfDocument.fromJson(jsonDecode(file.readAsStringSync()));
      final vm = SheetMetalStudioViewModel(initialDocument: baseDoc);
      vm.createCoverForCurrentFitting();
      expect(vm.hasCover, isTrue);

      final initialCoverMesh = vm.coverMesh;
      expect(initialCoverMesh, isNotNull);
      final initialBoundLength = initialCoverMesh!.boundLength;

      // Start Teach Scaling
      vm.startTeachScaling();
      expect(vm.isTeachScalingActive, isTrue);
      expect(vm.scalingController, isNotNull);

      // Morph port 2 width from 50 to 150 mm
      final ctrl = vm.scalingController!;
      ctrl.selectParameter('port2_width');
      ctrl.evaluateMorph(150.0);

      // Verify that coverMesh and currentMesh updated in REAL-TIME synchronously!
      final scaledCoverMesh = vm.coverMesh;
      expect(scaledCoverMesh, isNotNull);
      expect(scaledCoverMesh!.boundLength, greaterThan(initialBoundLength + 10.0));

      final combinedMesh = vm.currentMesh;
      expect(combinedMesh.boundLength, greaterThan(initialBoundLength + 10.0));

      // Accept scaling
      vm.acceptTeachScaling();
      expect(vm.isTeachScalingActive, isFalse);
      expect(vm.coverMesh!.boundLength, greaterThan(initialBoundLength + 10.0));
    });

    test('Test 14 — Non-Overlapping Guarantee when Base Part and Cover Expand', () {
      final file = File('assets/dxf_templates/trunking_accessories/unequal_tee_100x100x50x100x100x50x50.dsf');
      final baseDoc = DsfDocument.fromJson(jsonDecode(file.readAsStringSync()));
      final vm = SheetMetalStudioViewModel(initialDocument: baseDoc);
      vm.createCoverForCurrentFitting();

      void verifyNoOverlap(String phase) {
        final activeDoc = vm.document;
        final coverData = activeDoc.cover!;
        final baseBbox = TrunkingCoverGenerator.calculateDocumentBbox(activeDoc);
        final coverBbox = TrunkingCoverGenerator.calculateDocumentBbox(coverData.document);
        final coverWorldMinX = coverBbox.minX + coverData.offset2D.x;

        // Cover's left edge must strictly be greater than or equal to base's right edge
        expect(
          coverWorldMinX,
          greaterThanOrEqualTo(baseBbox.maxX),
          reason: '$phase: coverWorldMinX ($coverWorldMinX) must not overlap baseBbox.maxX (${baseBbox.maxX})',
        );
      }

      verifyNoOverlap('Initial State');

      // Expand fitting significantly (Port 2 width to 150mm)
      vm.startTeachScaling();
      final ctrl = vm.scalingController!;
      ctrl.selectParameter('port2_width');
      ctrl.evaluateMorph(150.0);

      verifyNoOverlap('During Real-Time Scaling to 150mm');

      // Expand fitting even further (Port 2 width to 200mm)
      ctrl.evaluateMorph(200.0);
      verifyNoOverlap('During Real-Time Scaling to 200mm');

      // Accept scaling
      vm.acceptTeachScaling();
      verifyNoOverlap('After Accepting Scaling');
    });

    test('Test 15 — 3D Cover Movement, Elevation Lift, and Custom Offset', () {
      final file = File('assets/dxf_templates/trunking_accessories/unequal_tee_100x100x50x100x100x50x50.dsf');
      final baseDoc = DsfDocument.fromJson(jsonDecode(file.readAsStringSync()));
      final vm = SheetMetalStudioViewModel(initialDocument: baseDoc);
      vm.createCoverForCurrentFitting();

      // Initially snapped to base
      vm.setCoverPlacementMode3D(CoverPlacementMode3D.snappedToBase);
      expect(vm.coverPlacementMode3D, equals(CoverPlacementMode3D.snappedToBase));
      expect(vm.coverOffset3D, equals(const CadPoint3D(0, 0, 0)));
      expect(vm.coverLiftZ, equals(0.0));
      expect(vm.document.cover!.properties['snappedClearanceZ'], equals(3.0));

      final initialCoverCenter = vm.coverMesh!.center;

      // 1. Lift cover vertically along Z (Exploded View)
      vm.setCoverLiftZ(60.0);
      expect(vm.coverLiftZ, equals(60.0));
      expect(vm.coverOffset3D.z, equals(60.0));
      expect(vm.coverMesh!.center.z, closeTo(initialCoverCenter.z + 60.0, 0.1));

      // 2. Translate cover freely in 3D (X, Y, Z delta)
      vm.updateCoverOffset3D(const CadPoint3D(25.0, -15.0, 10.0));
      expect(vm.coverPlacementMode3D, equals(CoverPlacementMode3D.custom));
      expect(vm.coverOffset3D.x, closeTo(25.0, 0.1));
      expect(vm.coverOffset3D.y, closeTo(-15.0, 0.1));
      expect(vm.coverOffset3D.z, closeTo(70.0, 0.1));
      expect(vm.coverMesh!.center.x, closeTo(initialCoverCenter.x + 25.0, 0.1));
      expect(vm.coverMesh!.center.y, closeTo(initialCoverCenter.y - 15.0, 0.1));
      expect(vm.coverMesh!.center.z, closeTo(initialCoverCenter.z + 70.0, 0.1));

      // 3. Reset 3D Offset
      vm.resetCover3DOffset();
      expect(vm.coverOffset3D, equals(const CadPoint3D(0, 0, 0)));
      expect(vm.coverMesh!.center.x, closeTo(initialCoverCenter.x, 0.1));

      // 4. Round-trip serialization preserves offset3D
      vm.updateCoverOffset3D(const CadPoint3D(10.0, 20.0, 50.0));
      final json = vm.document.toJson();
      final roundTrip = DsfDocument.fromJson(json);
      expect(roundTrip.cover, isNotNull);
      expect(roundTrip.cover!.offset3D.x, closeTo(10.0, 0.1));
      expect(roundTrip.cover!.offset3D.y, closeTo(20.0, 0.1));
      expect(roundTrip.cover!.offset3D.z, closeTo(50.0, 0.1));
      expect(roundTrip.cover!.placementMode3D, equals(CoverPlacementMode3D.custom));
    });
  });
}
