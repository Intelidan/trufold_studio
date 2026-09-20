// =============================================================================
// cms_ux_state.dart
//
// State machine and visual feedback state for the autonomous, observable CMS
// template authoring UX per TRUFOLD_LEGACY_ISOLATION_CLEAN_CMS_ARCHITECTURE.md (Section 12).
// =============================================================================

import 'package:flutter/foundation.dart';
import '../cad_primitives.dart';
import 'cms_physical_port.dart';
import 'cms_product_contract.dart';

/// Internal execution phases of the autonomous CMS state machine.
enum CmsUxPhase {
  idle,
  productSelected,
  analyzingFlatGeometry,
  suggestingBends,
  confirmingBends,
  folding,
  detectingOpenings,
  matchingPorts,
  classifyingCouplers,
  buildingConstraints,
  complete,
  ambiguityRequired,
  error,
}

/// Represents a candidate bend line proposed from geometric features (notches, crotches, shoulders).
@immutable
class CmsSuggestedBend {
  final String id;
  final CadPoint2D p1;
  final CadPoint2D p2;
  final bool isFlange;
  final String label;
  final double targetAngleDeg;
  final double radiusMm;

  const CmsSuggestedBend({
    required this.id,
    required this.p1,
    required this.p2,
    required this.isFlange,
    required this.label,
    this.targetAngleDeg = 90.0,
    this.radiusMm = 1.5,
  });
}

/// Represents a candidate 3D opening discovered from folded boundary loops.
@immutable
class CmsPortCandidate {
  final String candidateId;
  final double width;
  final double height;
  final CadPoint3D center;
  final CadPoint3D normal;
  final double matchScore;
  final String? matchedPortId;
  final bool isReliefOrNotch;

  const CmsPortCandidate({
    required this.candidateId,
    required this.width,
    required this.height,
    required this.center,
    required this.normal,
    this.matchScore = 1.0,
    this.matchedPortId,
    this.isReliefOrNotch = false,
  });
}

/// Active visual focus targets for synchronized 2D <-> 3D animated highlights.
@immutable
class CmsVisualFocus {
  final String? activePortId;
  final String? activeBendId;
  final String? activeFlangeId;
  final List<String> activePunchIds;

  const CmsVisualFocus({
    this.activePortId,
    this.activeBendId,
    this.activeFlangeId,
    this.activePunchIds = const [],
  });

  static const empty = CmsVisualFocus();
}

/// A milestone in the progressive narrative ("What TruFold Learned").
@immutable
class CmsLearnedMilestone {
  final String title;
  final String detail;
  final bool isVerified;

  const CmsLearnedMilestone({
    required this.title,
    required this.detail,
    this.isVerified = true,
  });
}

/// Autonomous, observable state for the clean CMS template authoring engine.
@immutable
class CmsUxState {
  final CmsUxPhase phase;
  final CmsProductContract? contract;
  final Map<int, ({double width, double height, double flange})> expectedPortDimensions;
  final List<CmsSuggestedBend> suggestedBends;
  final List<CmsPhysicalPort> discoveredPorts;
  final List<CmsPortCandidate> candidateOpenings;
  final List<String> verifiedBendIds;
  final List<String> verifiedFlangeIds;
  final List<String> classifiedCouplerPunchIds;
  final CmsVisualFocus focus;
  final List<CmsLearnedMilestone> learnedMilestones;
  final String stageTitle;
  final String stageSubtitle;
  final double progress;
  final String? activeErrorMessage;

  const CmsUxState({
    this.phase = CmsUxPhase.idle,
    this.contract,
    this.expectedPortDimensions = const {},
    this.suggestedBends = const [],
    this.discoveredPorts = const [],
    this.candidateOpenings = const [],
    this.verifiedBendIds = const [],
    this.verifiedFlangeIds = const [],
    this.classifiedCouplerPunchIds = const [],
    this.focus = CmsVisualFocus.empty,
    this.learnedMilestones = const [],
    this.stageTitle = 'Ready',
    this.stageSubtitle = '',
    this.progress = 0.0,
    this.activeErrorMessage,
  });

  bool get isActive => phase != CmsUxPhase.idle && phase != CmsUxPhase.complete;
  bool get hasAmbiguity => phase == CmsUxPhase.ambiguityRequired;
  bool get isComplete => phase == CmsUxPhase.complete;

  /// User-facing stage number (1 through 7) mapped from internal fine-grained phases.
  int get userStageNumber {
    switch (phase) {
      case CmsUxPhase.idle:
      case CmsUxPhase.productSelected:
        return 1;
      case CmsUxPhase.analyzingFlatGeometry:
      case CmsUxPhase.suggestingBends:
      case CmsUxPhase.confirmingBends:
        return 2;
      case CmsUxPhase.folding:
        return 3;
      case CmsUxPhase.detectingOpenings:
      case CmsUxPhase.matchingPorts:
      case CmsUxPhase.ambiguityRequired:
        return 4;
      case CmsUxPhase.classifyingCouplers:
        return 5;
      case CmsUxPhase.buildingConstraints:
        return 6;
      case CmsUxPhase.complete:
        return 7;
      case CmsUxPhase.error:
        return 0;
    }
  }

  /// User-facing title for the current stage.
  String get userStageName {
    switch (userStageNumber) {
      case 1:
        return 'Product Intent';
      case 2:
        return 'Bend Structure';
      case 3:
        return '3D Fold';
      case 4:
        return 'Physical Ports';
      case 5:
        return 'Feature Protection';
      case 6:
        return 'Smart Scaling';
      case 7:
        return 'Template Complete';
      default:
        return 'Error';
    }
  }

  /// High-level 3-Stage CMS Workflow Stage (1: Manufacturing Definition, 2: Automatic Port Mapping, 3: Teach Scaling)
  int get workflowStageIndex {
    switch (phase) {
      case CmsUxPhase.idle:
      case CmsUxPhase.productSelected:
      case CmsUxPhase.analyzingFlatGeometry:
      case CmsUxPhase.suggestingBends:
      case CmsUxPhase.confirmingBends:
        return 1;
      case CmsUxPhase.folding:
      case CmsUxPhase.detectingOpenings:
      case CmsUxPhase.matchingPorts:
      case CmsUxPhase.ambiguityRequired:
      case CmsUxPhase.classifyingCouplers:
      case CmsUxPhase.buildingConstraints:
      case CmsUxPhase.complete:
        return 2;
      case CmsUxPhase.error:
        return 0;
    }
  }

  /// User-facing name for the high-level 3-Stage CMS Workflow.
  String get workflowStageName {
    switch (workflowStageIndex) {
      case 1:
        return 'Stage 1: Manufacturing Definition';
      case 2:
        return 'Stage 2: Automatic Port Mapping';
      case 3:
        return 'Stage 3: Teach Scaling';
      default:
        return 'Error';
    }
  }

  CmsUxState copyWith({
    CmsUxPhase? phase,
    CmsProductContract? contract,
    Map<int, ({double width, double height, double flange})>? expectedPortDimensions,
    List<CmsSuggestedBend>? suggestedBends,
    List<CmsPhysicalPort>? discoveredPorts,
    List<CmsPortCandidate>? candidateOpenings,
    List<String>? verifiedBendIds,
    List<String>? verifiedFlangeIds,
    List<String>? classifiedCouplerPunchIds,
    CmsVisualFocus? focus,
    List<CmsLearnedMilestone>? learnedMilestones,
    String? stageTitle,
    String? stageSubtitle,
    double? progress,
    String? activeErrorMessage,
  }) {
    return CmsUxState(
      phase: phase ?? this.phase,
      contract: contract ?? this.contract,
      expectedPortDimensions: expectedPortDimensions ?? this.expectedPortDimensions,
      suggestedBends: suggestedBends ?? this.suggestedBends,
      discoveredPorts: discoveredPorts ?? this.discoveredPorts,
      candidateOpenings: candidateOpenings ?? this.candidateOpenings,
      verifiedBendIds: verifiedBendIds ?? this.verifiedBendIds,
      verifiedFlangeIds: verifiedFlangeIds ?? this.verifiedFlangeIds,
      classifiedCouplerPunchIds: classifiedCouplerPunchIds ?? this.classifiedCouplerPunchIds,
      focus: focus ?? this.focus,
      learnedMilestones: learnedMilestones ?? this.learnedMilestones,
      stageTitle: stageTitle ?? this.stageTitle,
      stageSubtitle: stageSubtitle ?? this.stageSubtitle,
      progress: progress ?? this.progress,
      activeErrorMessage: activeErrorMessage ?? this.activeErrorMessage,
    );
  }
}
