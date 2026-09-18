// =============================================================================
// cms_port_matching_and_reconciliation_test.dart
//
// Sprint 3 verification tests for Port Matching & Reconciliation
// per TRUFOLD_LEGACY_ISOLATION_CLEAN_CMS_ARCHITECTURE.md (Sprint 3).
// =============================================================================

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_physical_port.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_product_contract.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_3d_opening_detector.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_opening_plane_analyzer.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_port_matcher.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_port_reconciler.dart';

void main() {
  group('Sprint 3: Port Matching & Stable Reconciliation', () {
    late DsfDocument doc;
    late List<CmsMeasuredOpening> measuredOpenings;

    setUpAll(() async {
      final file = File('assets/dxf_templates/trunking_accessories/45_deg_bend_100x100.dsf');
      expect(file.existsSync(), isTrue);

      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      doc = DsfDocument.fromJson(json);

      // Fold document and analyze openings
      final foldResult = KinematicFoldEngine.foldDocument(doc, foldProgress: 1.0);
      final rawOpenings = Cms3DOpeningDetector.detectOpenings(
        document: doc,
        foldResult: foldResult,
      );
      measuredOpenings = rawOpenings.map((r) => CmsOpeningPlaneAnalyzer.analyze(raw: r, document: doc)).toList();
    });

    test('1. Matches 45° bend openings against CmsProductContract.bend45 with high confidence', () {
      expect(measuredOpenings.length, equals(2));

      final matchResult = CmsPortMatcher.match(
        measuredOpenings: measuredOpenings,
        contract: CmsProductContract.bend45,
      );

      expect(matchResult.isComplete, isTrue);
      expect(matchResult.requiresUserResolution, isFalse);
      expect(matchResult.overallConfidence, greaterThanOrEqualTo(0.9));
      expect(matchResult.matchedPorts.length, equals(2));

      final p1 = matchResult.matchedPorts[0];
      final p2 = matchResult.matchedPorts[1];

      expect(p1.id, equals('PORT_1'));
      expect(p1.width, closeTo(100.0, 5.0));
      expect(p1.suggestedRole, equals(CmsPortRole.bidirectional));

      expect(p2.id, equals('PORT_2'));
      expect(p2.width, closeTo(100.0, 5.0));
      expect(p2.suggestedRole, equals(CmsPortRole.bidirectional));
    });

    test('2. Requires user ambiguity resolution if candidate count contradicts contract', () {
      // Trying to match a 2-port bend against a 3-port Equal Tee contract
      final matchResult = CmsPortMatcher.match(
        measuredOpenings: measuredOpenings,
        contract: CmsProductContract.equalTee,
      );

      expect(matchResult.isComplete, isFalse);
      expect(matchResult.requiresUserResolution, isTrue);
      expect(matchResult.ambiguityReason, isNotNull);
      expect(matchResult.unmatchedCandidates.length, equals(2));
    });

    test('3. Reconciles and preserves stable port identities across scaling', () {
      // First matching
      final matchResult = CmsPortMatcher.match(
        measuredOpenings: measuredOpenings,
        contract: CmsProductContract.bend45,
      );
      final initialPorts = matchResult.matchedPorts;

      // Simulate scaled openings (Width scaled from 100 to 150 mm)
      final scaledOpenings = measuredOpenings.map<CmsMeasuredOpening>((m) {
        return CmsMeasuredOpening(
          openingId: m.openingId,
          width: 150.0,
          height: m.height,
          flange: m.flange,
          center: m.center,
          normal: m.normal,
          widthDirection: m.widthDirection,
          heightDirection: m.heightDirection,
          floorP1: m.floorP1,
          floorP2: m.floorP2,
          flatP1: m.flatP1,
          flatP2: m.flatP2,
          floorFaceId: m.floorFaceId,
          sidewallFaceIds: m.sidewallFaceIds,
        );
      }).toList();

      final reconciled = CmsPortReconciler.reconcile(
        previousPorts: initialPorts,
        newlyMeasured: scaledOpenings,
      );

      expect(reconciled.length, equals(2));
      expect(reconciled[0].id, equals('PORT_1'));
      expect(reconciled[0].width, equals(150.0), reason: 'Updated to scaled width');
      expect(reconciled[1].id, equals('PORT_2'));
      expect(reconciled[1].width, equals(150.0), reason: 'Updated to scaled width');
    });
  });
}
