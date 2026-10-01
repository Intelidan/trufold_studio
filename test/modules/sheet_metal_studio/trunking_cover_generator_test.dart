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
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/trunking_cover_data.dart';
import 'package:trufold_studio/sheet_metal_studio/models/planar_sheet_face.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_ux_state.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/covers/trunking_cover_generator.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/dxf_exporter.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_3d_opening_detector.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_opening_plane_analyzer.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/planar_face_decomposer.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/models/fold_bend_line.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';

void main() {
  group('TrunkingCoverGenerator Unit & Manufacturing Geometry Tests', () {
    test('Test 1 — Equal Tee Cover Generation (3 flanges, open ports, central mounting hole)', () {
      final teeFile = File('assets/dsf_templates/trunking_accessories/equal_tee_100x100.dsf');
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
      final teeFile = File('assets/dsf_templates/trunking_accessories/equal_tee_100x100.dsf');
      final json = jsonDecode(teeFile.readAsStringSync()) as Map<String, dynamic>;
      final baseDoc = DsfDocument.fromJson(json).copyWith(productType: 'Cable Trunking Unequal Tee', itemName: 'Unequal Tee 100x100x50x100x100x50x50');

      // User Scenario:
      // Port 1 = 100mm, Port 2 = 50mm, Port 3 = 75mm
      // Body Height = max(100, 50, 75) = 100mm
      // Port 1 Drop Flap = 100 - 100 = 0mm (no flap, open mouth)
      // Port 2 Drop Flap = 100 - 50 = 50mm (50mm extended 90° flap)
      // Port 3 Drop Flap = 100 - 75 = 25mm (25mm extended 90° flap)
      final coverData = TrunkingCoverGenerator.generateCover(baseDoc, parameterOverrides: {'port1_height': 100.0, 'port2_height': 50.0, 'port3_height': 75.0});

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
      final crossFile = File('assets/dsf_templates/trunking_accessories/equal_cross_100x100.dsf');
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
      final crossFile = File('assets/dsf_templates/trunking_accessories/equal_cross_100x100.dsf');
      final json = jsonDecode(crossFile.readAsStringSync()) as Map<String, dynamic>;
      final baseDoc = DsfDocument.fromJson(json).copyWith(productType: 'Cable Trunking Unequal Cross', itemName: 'Unequal Cross 100x50x100x50');

      // Scenario (Physical Port Layout: West=P1, North=P2, East=P3, South=P4):
      // Port 1 (West) = 50mm -> Drop = 50mm
      // Port 2 (North) = 100mm -> Hbody = 100mm -> Drop = 0mm (open)
      // Port 3 (East) = 50mm -> Drop = 50mm
      // Port 4 (South) = 100mm -> Drop = 0mm (open)
      final coverData = TrunkingCoverGenerator.generateCover(
        baseDoc,
        parameterOverrides: {'port1_height': 50.0, 'port2_height': 100.0, 'port3_height': 50.0, 'port4_height': 100.0},
      );

      expect(coverData, isNotNull);
      final coverDoc = coverData!.document;

      // Exactly 2 drop flaps (Ports 1 and 3)
      final dropFlaps = coverDoc.faces.where((f) => f.id.startsWith('C_DROP_F_')).toList();
      expect(dropFlaps.length, equals(2));
      for (final flap in dropFlaps) {
        expect(flap.label, contains('50.0mm'));
      }
      expect(dropFlaps.any((f) => f.label.contains('Port 1')), isTrue);
      expect(dropFlaps.any((f) => f.label.contains('Port 3')), isTrue);
      expect(dropFlaps.any((f) => f.label.contains('Port 2')), isFalse);
      expect(dropFlaps.any((f) => f.label.contains('Port 4')), isFalse);

      // Total bends: 4 corner cheek flanges + 2 drop flaps = 6 bends
      expect(coverDoc.bends.length, equals(6));
    });

    test('Test 5 — 45° Bend Cover Generation (inner and outer cheek flanges)', () {
      final bendFile = File('assets/dsf_templates/trunking_accessories/45_deg_bend_100x100.dsf');
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
      final teeFile = File('assets/dsf_templates/trunking_accessories/equal_tee_100x100.dsf');
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
      final teeFile = File('assets/dsf_templates/trunking_accessories/equal_tee_100x100.dsf');
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
      final teeFile = File('assets/dsf_templates/trunking_accessories/equal_tee_100x100.dsf');
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
      final teeFile = File('assets/dsf_templates/trunking_accessories/equal_tee_100x100.dsf');
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
      final teeFile = File('assets/dsf_templates/trunking_accessories/equal_tee_100x100.dsf');
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
      final file = File('assets/dsf_templates/trunking_accessories/unequal_tee_100x100x50x100x100x50x50.dsf');
      final baseDoc = DsfDocument.fromJson(jsonDecode(file.readAsStringSync()));

      final coverData = TrunkingCoverGenerator.generateCover(baseDoc);
      expect(coverData, isNotNull);
      final coverDoc = coverData!.document;

      // 1. Verify face composition: Main ceiling + side flanges + Port 2 drop flap
      final faceIds = coverDoc.faces.map((f) => f.id).toSet();
      expect(faceIds, contains('COVER_MAIN_FACE'));
      expect(faceIds, contains('C_DROP_F_1'));

      // 2. Verify Port 2 mouth bend line (includes defaultCoverClearanceOffset outward snug-fit clearance offset)
      final dropBend = coverDoc.bends.firstWhere((b) => b.id == 'C_DROP_B_1');
      final expectedX = 215.29 + TrunkingCoverGenerator.defaultCoverClearanceOffset;
      expect((dropBend.p1.x - expectedX).abs(), lessThan(0.1));
      expect((dropBend.p2.x - expectedX).abs(), lessThan(0.1));
      expect(dropBend.targetAngleDeg, equals(90.0));
      expect(dropBend.direction, equals(BendDirection.down));

      // 3. Verify 2D flap extends outward by 50mm
      final flapFace = coverDoc.faces.firstWhere((f) => f.id == 'C_DROP_F_1');
      final maxX = flapFace.vertices.map((v) => v.x).reduce(math.max);
      expect((maxX - (expectedX + 50.0)).abs(), lessThan(0.1));

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
      final file = File('assets/dsf_templates/trunking_accessories/unequal_cross_100x50x100x50.dsf');
      final baseDoc = DsfDocument.fromJson(jsonDecode(file.readAsStringSync()));

      final coverData = TrunkingCoverGenerator.generateCover(baseDoc);
      expect(coverData, isNotNull);
      final coverDoc = coverData!.document;

      // In Unequal Cross (100x50x100x50), Ports 1 & 3 (West & East) have 50mm height, while Ports 2 & 4 (North & South) have 100mm height
      // The cover should generate two 50mm drop flaps for Ports 1 & 3
      final dropFaces = coverDoc.faces.where((f) => f.id.startsWith('C_DROP_F_')).toList();
      expect(dropFaces.length, equals(2));
      expect(dropFaces.any((f) => f.label.contains('Port 1')), isTrue);
      expect(dropFaces.any((f) => f.label.contains('Port 3')), isTrue);
      expect(dropFaces.any((f) => f.label.contains('Port 2')), isFalse);
      expect(dropFaces.any((f) => f.label.contains('Port 4')), isFalse);

      for (final flap in dropFaces) {
        final flapPoly = KinematicFoldEngine.computeFold(doc: coverDoc, foldProgress: 1.0).firstWhere((p) => p.faceId == flap.id);
        final minZ = flapPoly.vertices.map((v) => v.z).reduce(math.min);
        final maxZ = flapPoly.vertices.map((v) => v.z).reduce(math.max);
        expect((maxZ - minZ - 50.0).abs(), lessThan(1.0));
      }
    });

    test('Test 13 — Real-time 3D Cover Scaling during CMS Teach Scaling', () {
      final file = File('assets/dsf_templates/trunking_accessories/unequal_tee_100x100x50x100x100x50x50.dsf');
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
      final file = File('assets/dsf_templates/trunking_accessories/unequal_tee_100x100x50x100x100x50x50.dsf');
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
      final file = File('assets/dsf_templates/trunking_accessories/unequal_tee_100x100x50x100x100x50x50.dsf');
      final baseDoc = DsfDocument.fromJson(jsonDecode(file.readAsStringSync()));
      final vm = SheetMetalStudioViewModel(initialDocument: baseDoc);
      vm.createCoverForCurrentFitting();

      // Initially snapped to base
      vm.setCoverPlacementMode3D(CoverPlacementMode3D.snappedToBase);
      expect(vm.coverPlacementMode3D, equals(CoverPlacementMode3D.snappedToBase));
      expect(vm.coverOffset3D, equals(const CadPoint3D(0, 0, 0)));
      expect(vm.coverLiftZ, equals(0.0));
      expect(vm.document.cover!.properties['snappedClearanceZ'], equals(5.0));

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

    test('Test 16 — 3D Viewport Facet Sorting & Occlusion (Solid Body, Cover Caps Flanges, No Bleed-through)', () {
      final file = File('assets/dsf_templates/trunking_accessories/45_deg_inside_riser_100x100.dsf');
      final baseDoc = DsfDocument.fromJson(jsonDecode(file.readAsStringSync()));
      final vm = SheetMetalStudioViewModel(initialDocument: baseDoc);
      vm.createCoverForCurrentFitting();

      final fullCoverMesh = vm.coverMesh!;
      final baseMesh = KinematicFoldEngine.foldDocument(baseDoc);

      List<String> getSortedFaceIds({required double azDeg, required double elDeg}) {
        final az = azDeg * math.pi / 180.0;
        final el = elDeg * math.pi / 180.0;
        final sinAz = math.sin(az), cosAz = math.cos(az);
        final sinEl = math.sin(el), cosEl = math.cos(el);

        ({Offset pt, double depth}) project(CadPoint3D p) {
          final rx = p.x - baseMesh.center.x;
          final ry = p.y - baseMesh.center.y;
          final rz = p.z - baseMesh.center.z;
          final x1 = rx * cosAz - ry * sinAz;
          final y1 = rx * sinAz + ry * cosAz;
          final z1 = rz;
          final x2 = x1;
          final y2 = y1 * cosEl - z1 * sinEl;
          final z2 = y1 * sinEl + z1 * cosEl;
          return (pt: Offset(x2, -y2), depth: z2);
        }

        CadPoint3D camNormal(CadPoint3D n) {
          final nx1 = n.x * cosAz - n.y * sinAz;
          final ny1 = n.x * sinAz + n.y * cosAz;
          final nz1 = n.z;
          final nx2 = nx1;
          final ny2 = ny1 * cosEl - nz1 * sinEl;
          final nz2 = ny1 * sinEl + nz1 * cosEl;
          return CadPoint3D(nx2, ny2, nz2);
        }

        final allPolys = [...baseMesh.polygons, ...fullCoverMesh.polygons];
        final items = allPolys
            .map((poly) {
              final prj = poly.vertices.map(project).toList();
              double minD = prj.first.depth, maxD = prj.first.depth;
              double minX = prj.first.pt.dx, maxX = prj.first.pt.dx;
              double minY = prj.first.pt.dy, maxY = prj.first.pt.dy;
              for (final p in prj) {
                if (p.depth < minD) minD = p.depth;
                if (p.depth > maxD) maxD = p.depth;
                if (p.pt.dx < minX) minX = p.pt.dx;
                if (p.pt.dx > maxX) maxX = p.pt.dx;
                if (p.pt.dy < minY) minY = p.pt.dy;
                if (p.pt.dy > maxY) maxY = p.pt.dy;
              }
              final nCam = camNormal(poly.normal);
              return (
                faceId: poly.faceId,
                depth: prj.fold(0.0, (acc, p) => acc + p.depth) / prj.length,
                minDepth: minD,
                maxDepth: maxD,
                bounds: Rect.fromLTRB(minX, minY, maxX, maxY),
                camNormal: nCam,
                p0Screen: prj.first.pt,
                p0Depth: prj.first.depth,
              );
            })
            .where((it) => it.camNormal.z > 0.0)
            .toList();

        double? depthAtItem(
          ({Rect bounds, CadPoint3D camNormal, double depth, String faceId, double maxDepth, double minDepth, double p0Depth, Offset p0Screen}) item,
          double sx,
          double sy,
        ) {
          final nz = item.camNormal.z;
          if (nz.abs() < 1e-4) return null;
          final p0 = item.p0Screen;
          final dx = sx - p0.dx;
          final dy = -(sy - p0.dy);
          final d = item.p0Depth - (item.camNormal.x * dx + item.camNormal.y * dy) / nz;
          return d.clamp(item.minDepth, item.maxDepth);
        }

        int facePri(String faceId) {
          if (faceId.startsWith('RIM_') || faceId.startsWith('CHAMFER_')) return 6;
          if (faceId.startsWith('COVER_MAIN') || faceId.endsWith('MAIN_FACE')) return 4;
          if (!faceId.startsWith('FILLET_') && !faceId.startsWith('BORE_') && !faceId.startsWith('COVER_CF_')) {
            return 3;
          }
          if (faceId.startsWith('COVER_CF_')) return 2;
          if (faceId.startsWith('BORE_')) return 2;
          if (faceId.startsWith('FILLET_')) return 1;
          return 3;
        }

        items.sort((a, b) {
          final isCoverA = a.faceId.contains('COVER');
          final isCoverB = b.faceId.contains('COVER');

          // 1. Within Cover assembly:
          if (isCoverA && isCoverB) {
            final isMainA = a.faceId.contains('MAIN');
            final isMainB = b.faceId.contains('MAIN');
            if (isMainA != isMainB) {
              return elDeg > 0 ? (isMainA ? 1 : -1) : (isMainA ? -1 : 1);
            }
            if (a.maxDepth < b.minDepth - 1.0) return -1;
            if (b.maxDepth < a.minDepth - 1.0) return 1;

            final depthDiff = a.depth - b.depth;
            if (depthDiff.abs() > 0.05) return depthDiff < 0 ? -1 : 1;
            final pa = facePri(a.faceId);
            final pb = facePri(b.faceId);
            return pa.compareTo(pb);
          }

          // 2. Between Cover and Base Fitting:
          if (isCoverA != isCoverB) {
            if (a.maxDepth < b.minDepth - 1.0) return -1;
            if (b.maxDepth < a.minDepth - 1.0) return 1;

            final overlap = a.bounds.intersect(b.bounds);
            if (overlap.width > 2.0 && overlap.height > 2.0) {
              final testPt = overlap.center;
              final dA = depthAtItem(a, testPt.dx, testPt.dy);
              final dB = depthAtItem(b, testPt.dx, testPt.dy);
              if (dA != null && dB != null) {
                final diff = dA - dB;
                if (diff.abs() > 1.5) return diff < 0 ? -1 : 1;
              }
              // Direct mechanical contact (< 1.5mm)
              return elDeg > 0 ? (isCoverA ? 1 : -1) : (isCoverA ? -1 : 1);
            }

            final depthDiff = a.depth - b.depth;
            if (depthDiff.abs() > 1.5) return depthDiff < 0 ? -1 : 1;
            return elDeg > 0 ? (isCoverA ? 1 : -1) : (isCoverA ? -1 : 1);
          }

          // 3. Between Base facets:
          if (a.maxDepth < b.minDepth - 1.0) return -1;
          if (b.maxDepth < a.minDepth - 1.0) return 1;

          final depthDiff = a.depth - b.depth;
          if (depthDiff.abs() > 0.05) return depthDiff < 0 ? -1 : 1;

          final pa = facePri(a.faceId);
          final pb = facePri(b.faceId);
          return pa.compareTo(pb);
        });

        return items.map((it) => it.faceId).toList();
      }

      // Verification 1: Azimuth = 45°, Elevation = 30°
      final order45 = getSortedFaceIds(azDeg: 45.0, elDeg: 30.0);
      final idxCoverMain45 = order45.indexOf('COVER_MAIN_FACE');
      final idxCheekF5_45 = order45.indexOf('F_5');
      final idxCheekF1_45 = order45.indexOf('F_1');
      final idxFloorF3_45 = order45.indexOf('F_3');

      expect(idxCoverMain45, greaterThanOrEqualTo(0));
      expect(idxCheekF5_45, greaterThan(idxCoverMain45), reason: 'Near cheek F_5 must occlude cover (drawn on top)');
      expect(idxCoverMain45, greaterThan(idxCheekF1_45), reason: 'Cover must occlude far cheek F_1');
      expect(idxCoverMain45, greaterThan(idxFloorF3_45), reason: 'Cover must occlude base floor F_3');

      for (final flangeId in ['COVER_CF_1', 'COVER_CF_2']) {
        final idx = order45.indexOf(flangeId);
        if (idx >= 0) {
          expect(idxCoverMain45, greaterThan(idx), reason: 'Cover main face must cap downward flange $flangeId (never inverted tray)');
        }
      }

      // Verification 2: Azimuth = -135°, Elevation = 30°
      final order135 = getSortedFaceIds(azDeg: -135.0, elDeg: 30.0);
      final idxCoverMain135 = order135.indexOf('COVER_MAIN_FACE');
      final idxFloorF3_135 = order135.indexOf('F_3');
      final idxSlopeF2_135 = order135.indexOf('F_2');

      expect(idxCoverMain135, greaterThan(idxFloorF3_135), reason: 'Cover must occlude base floor F_3');
      expect(idxCoverMain135, greaterThan(idxSlopeF2_135), reason: 'Cover must occlude slope F_2');

      for (final flangeId in ['COVER_CF_3', 'COVER_CF_4']) {
        final idx = order135.indexOf(flangeId);
        if (idx >= 0) {
          expect(idxCoverMain135, greaterThan(idx), reason: 'Cover main face must cap downward flange $flangeId');
        }
      }
    });

    test('Test 17 — Diagnose 45 deg bend face sorting', () {
      final bendFile = File('assets/dsf_templates/trunking_accessories/45_deg_bend_100x100.dsf');
      final json = jsonDecode(bendFile.readAsStringSync()) as Map<String, dynamic>;
      final baseDoc = DsfDocument.fromJson(json);
      final vm = SheetMetalStudioViewModel(initialDocument: baseDoc);
      vm.createCoverForCurrentFitting();

      final fullCoverMesh = vm.coverMesh!;
      final baseMesh = KinematicFoldEngine.foldDocument(baseDoc);



      // Test multiple azimuths around 0 to 90 degrees and print sorted order
      for (final az in [-45.0, 0.0, 45.0, 90.0, 135.0, 180.0, 225.0]) {
        final azRad = az * math.pi / 180.0;
        const elRad = 30.0 * math.pi / 180.0;
        final sinAz = math.sin(azRad), cosAz = math.cos(azRad);
        final sinEl = math.sin(elRad), cosEl = math.cos(elRad);

        ({Offset pt, double depth}) project(CadPoint3D p) {
          final rx = p.x - baseMesh.center.x;
          final ry = p.y - baseMesh.center.y;
          final rz = p.z - baseMesh.center.z;
          final x1 = rx * cosAz - ry * sinAz;
          final y1 = rx * sinAz + ry * cosAz;
          final z1 = rz;
          final x2 = x1;
          final y2 = y1 * cosEl - z1 * sinEl;
          final z2 = y1 * sinEl + z1 * cosEl;
          return (pt: Offset(x2, -y2), depth: z2);
        }

        CadPoint3D camNormal(CadPoint3D n) {
          final nx1 = n.x * cosAz - n.y * sinAz;
          final ny1 = n.x * sinAz + n.y * cosAz;
          final nz1 = n.z;
          final nx2 = nx1;
          final ny2 = ny1 * cosEl - nz1 * sinEl;
          final nz2 = ny1 * sinEl + nz1 * cosEl;
          return CadPoint3D(nx2, ny2, nz2);
        }

        final allPolys = [...baseMesh.polygons, ...fullCoverMesh.polygons];
        final items = allPolys.map((poly) {
          final prj = poly.vertices.map(project).toList();
          double minD = prj.first.depth, maxD = prj.first.depth;
          double minX = prj.first.pt.dx, maxX = prj.first.pt.dx;
          double minY = prj.first.pt.dy, maxY = prj.first.pt.dy;
          for (final p in prj) {
            if (p.depth < minD) minD = p.depth;
            if (p.depth > maxD) maxD = p.depth;
            if (p.pt.dx < minX) minX = p.pt.dx;
            if (p.pt.dx > maxX) maxX = p.pt.dx;
            if (p.pt.dy < minY) minY = p.pt.dy;
            if (p.pt.dy > maxY) maxY = p.pt.dy;
          }
          final nCam = camNormal(poly.normal);
          return (
            faceId: poly.faceId,
            depth: prj.fold(0.0, (acc, p) => acc + p.depth) / prj.length,
            minDepth: minD,
            maxDepth: maxD,
            bounds: Rect.fromLTRB(minX, minY, maxX, maxY),
            camNormal: nCam,
            p0Screen: prj.first.pt,
            p0Depth: prj.first.depth,
          );
        }).where((it) => it.camNormal.z > 0.0).toList();

        int facePri(String faceId) {
          if (faceId.startsWith('RIM_') || faceId.startsWith('CHAMFER_')) return 6;
          if (faceId.startsWith('COVER_MAIN') || faceId.endsWith('MAIN_FACE')) return 4;
          if (!faceId.endsWith('_BOT') && !faceId.startsWith('FILLET_') && !faceId.startsWith('BORE_') && !faceId.startsWith('COVER_CF_')) {
            return 3;
          }
          if (faceId.startsWith('COVER_CF_')) return 2;
          if (faceId.startsWith('BORE_')) return 2;
          if (faceId.startsWith('FILLET_')) return 1;
          return 3;
        }

        items.sort((a, b) {
          final isCoverA = a.faceId.contains('COVER');
          final isCoverB = b.faceId.contains('COVER');

          // 1. Within Cover assembly:
          if (isCoverA && isCoverB) {
            final isMainA = a.faceId.contains('MAIN');
            final isMainB = b.faceId.contains('MAIN');
            if (isMainA != isMainB) {
              return 30.0 > 0 ? (isMainA ? 1 : -1) : (isMainA ? -1 : 1);
            }
            if (a.maxDepth < b.minDepth - 1.0) return -1;
            if (b.maxDepth < a.minDepth - 1.0) return 1;

            final depthDiff = a.depth - b.depth;
            if (depthDiff.abs() > 0.05) return depthDiff < 0 ? -1 : 1;
            final pa = facePri(a.faceId);
            final pb = facePri(b.faceId);
            return pa.compareTo(pb);
          }

          // 2. Between Cover and Base Fitting:
          if (isCoverA != isCoverB) {
            if (a.maxDepth < b.minDepth - 1.0) return -1;
            if (b.maxDepth < a.minDepth - 1.0) return 1;

            final depthDiff = a.depth - b.depth;
            if (depthDiff.abs() > 1.5) return depthDiff < 0 ? -1 : 1;
            return 30.0 > 0 ? (isCoverA ? 1 : -1) : (isCoverA ? -1 : 1);
          }

          // 3. Between Base facets:
          if (a.maxDepth < b.minDepth - 1.0) return -1;
          if (b.maxDepth < a.minDepth - 1.0) return 1;

          final depthDiff = a.depth - b.depth;
          if (depthDiff.abs() > 0.05) return depthDiff < 0 ? -1 : 1;
          final pa = facePri(a.faceId);
          final pb = facePri(b.faceId);
          return pa.compareTo(pb);
        });

        // Verify items sorted without error
        expect(items, isNotEmpty);
      }
    });

    test('Test 18 — 45° Bend Cover: Flanges wrap only on sidewalls, 0 flanges on port mouths (SS1)', () {
      final bendFile = File('assets/dsf_templates/trunking_accessories/45_deg_bend_100x100.dsf');
      final json = jsonDecode(bendFile.readAsStringSync()) as Map<String, dynamic>;
      final baseDoc = DsfDocument.fromJson(json);

      final coverData = TrunkingCoverGenerator.generateCover(baseDoc);
      expect(coverData, isNotNull);
      final coverDoc = coverData!.document;

      // 45° bend cover has 5-sided main face
      final mainFace = coverDoc.faces.firstWhere((f) => f.id == 'COVER_MAIN_FACE');
      expect(mainFace.vertices.length, equals(5));

      // Side wall flanges: exactly 3 flanges (top horizontal sidewall B1, and 2 bottom sidewalls B2/B3)
      final flangeFaces = coverDoc.faces.where((f) => f.id.startsWith('CF_')).toList();
      expect(flangeFaces.length, equals(3), reason: 'Must have 3 sidewall flanges and 0 port mouth flanges');

      // Bends: exactly 3 down-folds for the 3 sidewall flanges
      expect(coverDoc.bends.length, equals(3));

      // Port 1 and Port 2 mouths have no flanges and no bends
      final dropFlapFaces = coverDoc.faces.where((f) => f.id.startsWith('C_DROP_')).toList();
      expect(dropFlapFaces, isEmpty, reason: '45 deg bend has no drop flaps or port flanges');
    });

    test('Test 19 — 45° Inside Riser Cover: Reduced length to horizontal flat opening, 0 port flanges (SS2)', () {
      final riserFile = File('assets/dsf_templates/trunking_accessories/45_deg_inside_riser_100x100.dsf');
      final json = jsonDecode(riserFile.readAsStringSync()) as Map<String, dynamic>;
      final baseDoc = DsfDocument.fromJson(json);

      final coverData = TrunkingCoverGenerator.generateCover(baseDoc);
      expect(coverData, isNotNull);
      final coverDoc = coverData!.document;

      // Main face matches reduced horizontal opening (rectangular)
      final mainFace = coverDoc.faces.firstWhere((f) => f.id == 'COVER_MAIN_FACE');
      expect(mainFace.vertices.length, equals(4));

      final xs = mainFace.vertices.map((v) => v.x).toList();
      final ys = mainFace.vertices.map((v) => v.y).toList();
      final lengthY = ys.reduce(math.max) - ys.reduce(math.min);
      final widthX = xs.reduce(math.max) - xs.reduce(math.min);

      // Width matches channel width (~96mm + snug fit ~99mm)
      expect(widthX, closeTo(99.0, 3.0));

      // Length matches top horizontal flat opening (~55.6mm), NOT the full base floor (98.65mm)
      expect(lengthY, closeTo(55.64, 2.0), reason: 'Cover length must match horizontal flat opening only and not extend over 45° coupler prongs');

      // Flanges wrap only on lateral sidewalls (left & right): exactly 2 flanges
      final flangeFaces = coverDoc.faces.where((f) => f.id.startsWith('CF_')).toList();
      expect(flangeFaces.length, equals(2), reason: 'Must have exactly 2 lateral sidewall flanges');
      expect(coverDoc.bends.length, equals(2));

      // 0 port flanges
      final dropFlapFaces = coverDoc.faces.where((f) => f.id.startsWith('C_DROP_')).toList();
      expect(dropFlapFaces, isEmpty);
    });

    test('Test 20 — 45° Outside Riser Cover: Covers whole straight top opening, 0 port flanges (SS3)', () {
      final riserFile = File('assets/dsf_templates/trunking_accessories/45_deg_outside_riser_100x100.dsf');
      final json = jsonDecode(riserFile.readAsStringSync()) as Map<String, dynamic>;
      final baseDoc = DsfDocument.fromJson(json);

      final coverData = TrunkingCoverGenerator.generateCover(baseDoc);
      expect(coverData, isNotNull);
      final coverDoc = coverData!.document;

      final mainFace = coverDoc.faces.firstWhere((f) => f.id == 'COVER_MAIN_FACE');
      expect(mainFace.vertices.length, equals(4));

      final xs = mainFace.vertices.map((v) => v.x).toList();
      final ys = mainFace.vertices.map((v) => v.y).toList();
      final lengthY = ys.reduce(math.max) - ys.reduce(math.min);
      final widthX = xs.reduce(math.max) - xs.reduce(math.min);

      // Width matches channel width (~97mm + snug fit ~100mm)
      expect(widthX, closeTo(100.0, 3.0));

      // Length covers the whole straight top opening up to the 45° knee (~103.4mm), NOT just the base floor (63.7mm) or return flange (93.4mm)
      expect(lengthY, closeTo(103.4, 2.0), reason: 'Cover length must cover the whole straight top opening up to the 45° knee');

      // Flanges wrap on lateral sidewalls: 2 on main flat roof and 2 on angled extension = 4 flanges
      final flangeFaces = coverDoc.faces.where((f) => f.id.startsWith('CF_')).toList();
      expect(flangeFaces.length, equals(4), reason: 'Must have 4 lateral sidewall flanges (2 main, 2 angled)');
      expect(coverDoc.bends.length, equals(5), reason: '1 roof bend (45°) and 4 side flange bends (90°)');

      // 45° angled extension face exists
      final extFace = coverDoc.faces.firstWhere((f) => f.id == 'COVER_EXT_FACE_1');
      expect(extFace, isNotNull);

      // 0 port mouth drop flaps
      final dropFlapFaces = coverDoc.faces.where((f) => f.id.startsWith('C_DROP_')).toList();
      expect(dropFlapFaces, isEmpty);

      // Verify 3D folded mesh coordinates: cover spans from Y ~ 30.0 to Y ~ 133.42 on flat roof,
      // and extends down at 45° towards coupler flap on COVER_EXT_FACE_1
      final coverMesh = KinematicFoldEngine.foldDocument(coverDoc, foldProgress: 1.0);
      expect(coverMesh.polygons, isNotEmpty);
      final mainPoly = coverMesh.polygons.firstWhere((p) => p.faceId == 'COVER_MAIN_FACE');
      final pYs = mainPoly.vertices.map((v) => v.y).toList();
      expect(pYs.reduce(math.min), closeTo(30.0, 1.0), reason: 'Cover starts after coupler flap at Y ~ 30.0');
      expect(pYs.reduce(math.max), closeTo(133.42, 1.0), reason: 'Cover extends to 45° knee at Y ~ 133.42');

      final extPoly = coverMesh.polygons.firstWhere((p) => p.faceId == 'COVER_EXT_FACE_1');
      expect(extPoly.normal.y.abs(), closeTo(0.707, 0.05), reason: 'Extended portion slopes at 45°');
      expect(extPoly.normal.z, closeTo(0.707, 0.05), reason: 'Extended portion slopes at 45°');
    });

    test('Test 21 — 90° Bend: Accurate Port Mapping & Cover Generation (SS1 & SS2)', () async {
      final bendFile = File('assets/dsf_templates/trunking_accessories/90_deg_bend_100x100.dsf');
      final json = jsonDecode(bendFile.readAsStringSync()) as Map<String, dynamic>;
      final baseDoc = DsfDocument.fromJson(json);

      // 1. Planar face decomposition must identify F_6 as base floor
      final decomp = PlanarFaceDecomposer.decompose(
        outerContour: baseDoc.outerContour,
        bends: baseDoc.bends,
        cutLines: baseDoc.cutLines,
      );
      for (final f in decomp.faces) {
        // ignore: avoid_print
        print('${f.id}: role=${f.role} label=${f.label} isBase=${f.isBaseAnchor} area=${f.areaMm2}');
      }
      final baseFace = decomp.faces.firstWhere((f) => f.id == decomp.baseFaceId);
      expect(baseFace.role, equals(FaceRole.baseFloor));
      expect(baseFace.isBaseAnchor, isTrue);
      expect(baseFace.areaMm2, closeTo(13286.0, 5.0), reason: 'Central base floor web connecting sidewalls must be chosen as base floor');

      final docToFold = baseDoc.copyWith(
        bends: decomp.connectedBends,
        faces: decomp.faces,
        baseFaceId: decomp.baseFaceId,
      );

      // 2. Fold 3D representation
      final foldResult = KinematicFoldEngine.foldDocument(docToFold, foldProgress: 1.0);
      expect(foldResult.polygons, isNotEmpty);

      // 2. Discover physical openings (SS1)
      final rawOpenings = Cms3DOpeningDetector.detectOpenings(
        document: docToFold,
        foldResult: foldResult,
      );
      for (final r in rawOpenings) {
        // ignore: avoid_print
        print('Raw opening: p1=${r.flatFloorEdgeP1} p2=${r.flatFloorEdgeP2} len=${r.flatFloorEdgeP1.distanceTo(r.flatFloorEdgeP2)} normal=${r.outwardNormal}');
      }
      expect(rawOpenings.length, equals(2), reason: 'Must detect exactly 2 physical port openings (Port 1 and Port 2)');

      final measuredList = rawOpenings.map((raw) {
        return CmsOpeningPlaneAnalyzer.analyze(raw: raw, document: docToFold, foldResult: foldResult);
      }).toList();
      expect(measuredList.length, equals(2));
      for (final m in measuredList) {
        expect(m.width, closeTo(98.0, 5.0), reason: 'Channel mouth width ~98-100mm');
        expect(m.height, closeTo(100.0, 5.0), reason: 'Sidewall height ~100mm');
        expect(m.normal.z.abs(), lessThan(0.05), reason: 'Port mouth normal must be horizontal');
      }

      // 3. Generate Cover (SS2)
      bendFile.writeAsStringSync(jsonEncode(docToFold.toJson()));
      final coverData = TrunkingCoverGenerator.generateCover(docToFold);
      expect(coverData, isNotNull);
      final coverDoc = coverData!.document;

      // Cover main face is 6-sided polygon matching base floor F_6
      final mainFace = coverDoc.faces.firstWhere((f) => f.id == 'COVER_MAIN_FACE');
      expect(mainFace.vertices.length, equals(6));

      // Side wall flanges: exactly 4 flanges (2 outer cheeks, outer center wall, inner center wall)
      final flangeFaces = coverDoc.faces.where((f) => f.id.startsWith('CF_')).toList();
      expect(flangeFaces.length, equals(4), reason: 'Must wrap over only on the 4 sidewalls');
      expect(coverDoc.bends.length, equals(4));

      // Port 1 and Port 2 mouths have 0 flanges
      final dropFlapFaces = coverDoc.faces.where((f) => f.id.startsWith('C_DROP_')).toList();
      expect(dropFlapFaces, isEmpty, reason: 'No cover flanges on the Port openings side');

      // 4. 3D Cover Placement via ViewModel: floating 2 to 3mm above flange
      final vm = SheetMetalStudioViewModel(initialDocument: docToFold);
      await vm.continueCmsPortMapping();
      expect(vm.persistentCmsPorts.length, equals(2), reason: 'Must auto-map exactly 2 ports');
      expect(vm.cmsGuidedController.state.phase, equals(CmsUxPhase.complete));

      vm.createCoverForCurrentFitting();
      expect(vm.coverMesh, isNotNull);
      expect(vm.document.cover!.properties['snappedClearanceZ'], equals(5.0));
      final cover3D = vm.coverMesh!;
      final mainPoly = cover3D.polygons.firstWhere((p) => p.faceId.contains('MAIN_FACE'));
      final zValues = mainPoly.vertices.map((v) => v.z).toList();
      expect(zValues.every((z) => (z - 105.0).abs() < 1.5), isTrue, reason: 'Cover plate sits at bodyHeight (100.0mm) + clearance (5mm) = 105.0mm');
    });
  });
}
