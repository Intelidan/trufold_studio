// =============================================================================
// cms_coupler_classification_test.dart
//
// Sprint 5 verification tests for Coupler Classification & Rigid Invariant Locking
// per TRUFOLD_LEGACY_ISOLATION_CLEAN_CMS_ARCHITECTURE.md (Sprint 5).
// =============================================================================

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cnc_punch_primitive.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_product_contract.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_3d_opening_detector.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_opening_plane_analyzer.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_port_matcher.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_coupler_classifier.dart';

void main() {
  group('Sprint 5: Coupler Feature Classification & Rigid Invariant Locking', () {
    test('1. Accurately identifies 8 coupler slots on 45_deg_bend_100x100.dsf and associates with ports', () async {
      final file = File('assets/dsf_templates/trunking_accessories/45_deg_bend_100x100.dsf');
      expect(file.existsSync(), isTrue);

      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final doc = DsfDocument.fromJson(json);

      // Verify initial punches count
      expect(doc.punches.length, equals(8));

      // Match physical ports
      final foldResult = KinematicFoldEngine.foldDocument(doc, foldProgress: 1.0);
      final rawOpenings = Cms3DOpeningDetector.detectOpenings(
        document: doc,
        foldResult: foldResult,
      );
      final measured = rawOpenings.map((r) => CmsOpeningPlaneAnalyzer.analyze(raw: r, document: doc)).toList();
      final matchResult = CmsPortMatcher.match(
        measuredOpenings: measured,
        contract: CmsProductContract.bend45,
      );
      expect(matchResult.isComplete, isTrue);

      // Classify punches
      final classification = CmsCouplerClassifier.classify(
        document: doc,
        contract: CmsProductContract.bend45,
        ports: matchResult.matchedPorts,
      );

      expect(classification.matchesContract, isTrue);
      expect(classification.couplerSlots.length, equals(8));
      expect(classification.confidence, equals(1.0));

      for (final p in classification.couplerSlots) {
        expect(p.role, equals(CncPunchRole.coupler));
        expect((p.widthMm - 8.0).abs(), lessThan(1e-3));
        expect((p.lengthMm - 12.0).abs(), lessThan(1e-3));
      }

      // 4 slots per port (2 per sidewall)
      expect(classification.couplerSlotsByPort['PORT_1']?.length, equals(4));
      expect(classification.couplerSlotsByPort['PORT_2']?.length, equals(4));
    });

    test('2. Floor perforations are never classified as coupler slots and survive round-trip reopening', () {
      final file = File('assets/dsf_templates/trunking_accessories/45_deg_bend_100x100.dsf');
      final content = file.readAsStringSync();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final baseDoc = DsfDocument.fromJson(json);

      // Add a base floor perforation slot (7x25mm) right in the middle of base floor
      final floorPunch = CncPunchPrimitive(
        id: 'FLOOR_PERF_1',
        type: PunchType.obroundSlot,
        center: const CadPoint2D(150, 150),
        widthMm: 7.0,
        lengthMm: 25.0,
        role: CncPunchRole.perforation,
      );

      final docWithFloor = baseDoc.copyWith(
        punches: [...baseDoc.punches, floorPunch],
      );

      // Classify
      final res = CmsCouplerClassifier.classify(
        document: docWithFloor,
        contract: CmsProductContract.bend45,
      );

      // Coupler slots should still be only the 8 sidewall slots
      expect(res.couplerSlots.length, equals(8));
      expect(res.perforations.any((p) => p.id == 'FLOOR_PERF_1'), isTrue);

      // Simulate saving with corrupt couplerSlotPunchIds containing all punch IDs
      final docMap = docWithFloor.toJson();
      final meta = Map<String, dynamic>.from(docMap['metadata'] as Map);
      final cms = Map<String, dynamic>.from(meta['cmsTemplate'] as Map? ?? {});
      cms['couplerSlotPunchIds'] = docWithFloor.punches.map((p) => p.id).toList(); // includes FLOOR_PERF_1!
      meta['cmsTemplate'] = cms;
      docMap['metadata'] = meta;

      // Reopen document from JSON
      final reopened = DsfDocument.fromJson(docMap);
      final reopenedFloorPunch = reopened.punches.firstWhere((p) => p.id == 'FLOOR_PERF_1');
      expect(reopenedFloorPunch.role, equals(CncPunchRole.perforation));
      expect(reopenedFloorPunch.isCoupler, isFalse);
    });
  });
}
