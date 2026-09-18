// =============================================================================
// cms_domain_models_test.dart
//
// Sprint 1 verification tests for clean CMS domain models
// per TRUFOLD_LEGACY_ISOLATION_CLEAN_CMS_ARCHITECTURE.md.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_physical_port.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_product_contract.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_ux_state.dart';

void main() {
  group('Clean CMS Domain Models (Sprint 1)', () {
    test('1. CmsPhysicalPort preserves physical factual geometry independent of flow role', () {
      const port = CmsPhysicalPort(
        id: 'PORT_1',
        index: 1,
        width: 100.0,
        height: 100.0,
        flange: 15.0,
        center: CadPoint3D(50, 0, 50),
        normal: CadPoint3D(0, -1, 0),
        widthDirection: CadPoint3D(1, 0, 0),
        heightDirection: CadPoint3D(0, 0, 1),
        hostFaceIds: ['F_floor', 'F_wall_L', 'F_wall_R'],
        boundaryLoopId: 'loop_port1',
        confidence: 0.98,
        detectionSource: PortDetectionSource.foldedTopology,
      );

      expect(port.id, equals('PORT_1'));
      expect(port.width, equals(100.0));
      expect(port.height, equals(100.0));
      expect(port.normal.y, equals(-1.0));
      expect(port.role, isNull); // Flow role is unassigned by default
      expect(port.isHighConfidence, isTrue);

      // JSON serialization & deserialization round-trip
      final json = port.toJson();
      final revived = CmsPhysicalPort.fromJson(json);

      expect(revived.id, equals('PORT_1'));
      expect(revived.width, equals(100.0));
      expect(revived.height, equals(100.0));
      expect(revived.center.x, equals(50.0));
      expect(revived.normal.y, equals(-1.0));
      expect(revived.detectionSource, equals(PortDetectionSource.foldedTopology));
    });

    test('2. CmsProductContract correctly specifies 45 Deg Bend topology and disambiguates Unequal Tee', () {
      final bendContract = CmsProductContract.lookup('bend', '45_deg_bend');
      expect(bendContract, isNotNull);
      expect(bendContract!.expectedPortCount, equals(2));
      expect(bendContract.expectedStructuralBends, equals(3));
      expect(bendContract.expectedFlanges, equals(2));
      expect(bendContract.totalExpectedCouplerSlots, equals(8));

      // Disambiguation: unequal_tee must not falsely match equal_tee
      final unequalTee = CmsProductContract.lookup('tee', 'unequal_tee');
      final equalTee = CmsProductContract.lookup('tee', 'equal_tee');

      expect(unequalTee, isNotNull);
      expect(equalTee, isNotNull);
      expect(unequalTee!.variationName, equals('unequal_tee'));
      expect(equalTee!.variationName, equals('equal_tee'));
      expect(unequalTee.hasRoleSuggestionRule, isTrue);
      expect(equalTee.hasRoleSuggestionRule, isFalse);
    });

    test('3. CmsUxState models autonomous phases, visual focus, and narrative milestones', () {
      var state = const CmsUxState();
      expect(state.phase, equals(CmsUxPhase.idle));
      expect(state.isActive, isFalse);

      state = state.copyWith(
        phase: CmsUxPhase.analyzingFlatGeometry,
        contract: CmsProductContract.bend45,
        stageTitle: 'Analyzing 45° Bend',
        stageSubtitle: 'Reading DSF bend data...',
        progress: 0.25,
      );

      expect(state.isActive, isTrue);
      expect(state.progress, equals(0.25));

      // Visual focus targets
      state = state.copyWith(
        focus: const CmsVisualFocus(
          activePortId: 'PORT_1',
          activeBendId: 'B1',
        ),
        learnedMilestones: [
          const CmsLearnedMilestone(title: 'Product', detail: '45° Bend'),
          const CmsLearnedMilestone(title: 'Ports', detail: '2 Physical Ports Discovered'),
        ],
      );

      expect(state.focus.activePortId, equals('PORT_1'));
      expect(state.focus.activeBendId, equals('B1'));
      expect(state.learnedMilestones.length, equals(2));
      expect(state.learnedMilestones.first.detail, equals('45° Bend'));
    });
  });
}
