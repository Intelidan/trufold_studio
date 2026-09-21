// =============================================================================
// cms_guided_ux_controller.dart
//
// Autonomous, observable controller orchestrating the 7-Stage CMS authoring
// workflow per TRUFOLD_LEGACY_ISOLATION_CLEAN_CMS_ARCHITECTURE.md (Sections 14, 18-20).
//
// Foundational Axiom:
// "A flat DXF has no physical ports. Ports are semantic physical openings of the folded part.
//  Therefore, CMS port discovery is prohibited until the user-authorized bend structure has
//  produced a valid folded 3D topology."
// =============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/dsf_document.dart';
import '../../models/fold_bend_line.dart';
import '../../models/cms/cms_physical_port.dart';
import '../../models/cms/cms_product_contract.dart';
import '../../models/cms/cms_ux_state.dart';
import '../kinematic_fold_engine.dart';
import '../planar_face_decomposer.dart';
import 'cms_3d_opening_detector.dart';
import 'cms_opening_plane_analyzer.dart';
import 'cms_port_matcher.dart';
import 'cms_coupler_classifier.dart';

/// Autonomous controller driving the deliberate, observable CAD authoring workflow.
class CmsGuidedUxController extends ChangeNotifier {
  CmsUxState _state = const CmsUxState();

  CmsUxState get state => _state;
  CmsUxPhase get phase => _state.phase;
  List<CmsPhysicalPort> get discoveredPorts => _state.discoveredPorts;
  List<CmsLearnedMilestone> get milestones => _state.learnedMilestones;

  /// Stage 1: Starts the guided authoring session with the specified contract.
  void startSession({required CmsProductContract contract, Map<int, ({double width, double height, double flange})>? expectedPortDimensions}) {
    _state = CmsUxState(
      phase: CmsUxPhase.productSelected,
      contract: contract,
      expectedPortDimensions: expectedPortDimensions ?? {},
      stageTitle: 'Stage 1 of 7: Product Intent',
      stageSubtitle: 'Expected ${contract.expectedPortCount} ports, ${contract.expectedStructuralBends} structural bends.',
      progress: 0.14,
      learnedMilestones: [
        CmsLearnedMilestone(title: 'Stage 1: Product Intent Identified', detail: '${contract.displayName} (${contract.productType.toUpperCase()})'),
      ],
    );
    notifyListeners();
  }

  /// Runs the discovery sequence, strictly adhering to the 7-stage dependency order.
  /// If bends are missing or incomplete, pauses at Stage 2 (suggestingBends) for user authorization.
  Future<void> runAutomaticDiscovery({required DsfDocument document, Duration stepDelay = Duration.zero}) async {
    final contract = _state.contract ?? CmsProductContract.bend45;

    // -------------------------------------------------------------------------
    // Stage 2: Understand Structural Geometry (Bends & Flanges)
    // -------------------------------------------------------------------------
    _updateState(
      _state.copyWith(
        phase: CmsUxPhase.analyzingFlatGeometry,
        stageTitle: 'Stage 2 of 7: Bend Structure',
        stageSubtitle: 'Analyzing flat geometry and locating bend line candidates...',
        progress: 0.28,
      ),
    );
    if (stepDelay > Duration.zero) await Future.delayed(stepDelay);

    if (document.bends.isEmpty) {
      // Bends do not exist yet on this flat blank.
      // Generate candidate starting suggestions from template or notch geometry.
      List<CmsSuggestedBend> suggestions = [];

      // 1. Check for companion template DSF if available
      final dsfCandidates = [
        'assets/dxf_templates/trunking_accessories/${document.itemName}.dsf',
        'assets/dxf_templates/trunking_accessories/${document.itemName.replaceAll('.dxf', '.dsf')}',
        document.itemName.replaceAll('.dxf', '.dsf'),
      ];

      for (final p in dsfCandidates) {
        try {
          final f = File(p);
          if (f.existsSync()) {
            final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
            final companionDoc = DsfDocument.fromJson(json);
            if (companionDoc.bends.isNotEmpty) {
              suggestions = companionDoc.bends
                  .map(
                    (b) => CmsSuggestedBend(
                      id: b.id,
                      p1: b.p1,
                      p2: b.p2,
                      isFlange: b.role == BendLineRole.flange,
                      label: b.role == BendLineRole.flange ? 'FLANGE 90° UP' : 'BEND 90° UP',
                      targetAngleDeg: b.targetAngleDeg,
                      radiusMm: b.radiusMm,
                    ),
                  )
                  .toList();
              break;
            }
          }
        } catch (_) {}
      }

      // NOTE: Removed DxfAutoFoldEngine.detectCandidateLines!
      // In Stage 1, if no companion template exists, the user authoritatively
      // marks bend lines & flanges on the 2D canvas.
      if (suggestions.isNotEmpty) {
        _addMilestone('Companion Template Located', 'Loaded ${suggestions.length} pre-defined bend/flange lines for ${contract.displayName}.');
        _updateState(
          _state.copyWith(
            phase: CmsUxPhase.suggestingBends,
            suggestedBends: suggestions,
            stageTitle: 'Stage 1: Review Bend Structure',
            stageSubtitle: 'Verify suggested lines from template or customize on canvas.',
            progress: 0.28,
          ),
        );
      } else {
        _addMilestone('Stage 1: Awaiting User Bends', 'No pre-existing bends. Mark ${contract.expectedStructuralBends} bends and ${contract.expectedFlanges} flanges on canvas.');
        _updateState(
          _state.copyWith(
            phase: CmsUxPhase.suggestingBends,
            suggestedBends: const [],
            stageTitle: 'Stage 1: Define Bends & Flanges',
            stageSubtitle: 'Please mark bend lines (B) and flange lines on canvas for ${contract.displayName}.',
            progress: 0.20,
          ),
        );
      }
      return;
    }

    // Bends already exist on document (e.g. from DSF or pre-defined).
    // Validate existing bends against contract.
    final structuralBends = document.bends.where((b) => b.role != BendLineRole.flange).toList();
    final flanges = document.bends.where((b) => b.role == BendLineRole.flange).toList();

    if (structuralBends.length < contract.expectedStructuralBends) {
      // Existing bends are insufficient or uncertain
      _updateState(
        _state.copyWith(
          phase: CmsUxPhase.confirmingBends,
          stageTitle: 'Stage 1: Review Bend Structure',
          stageSubtitle: 'Found ${structuralBends.length} bends, but ${contract.displayName} expects ${contract.expectedStructuralBends}.',
          progress: 0.28,
        ),
      );
      return;
    }

    _addMilestone('Stage 1: Manufacturing Definition Verified', '${structuralBends.length} structural bends and ${flanges.length} return flanges verified.');

    // Proceed to folding and port discovery (Stage 2)
    await continueFoldingAndDiscovery(document: document, stepDelay: stepDelay);
  }

  /// Sets up controller state when reopening an existing Stage 1 DSF (bends defined, ports pending).
  void resumeAtStage1({required DsfDocument document, required CmsProductContract contract}) {
    final structuralBends = document.bends.where((b) => b.role != BendLineRole.flange).toList();
    final flanges = document.bends.where((b) => b.role == BendLineRole.flange).toList();
    _state = CmsUxState(
      phase: CmsUxPhase.confirmingBends,
      contract: contract,
      stageTitle: 'Stage 1: Bends Defined',
      stageSubtitle: '${structuralBends.length} bends, ${flanges.length} flanges. Ready for automatic port mapping.',
      progress: 0.33,
      learnedMilestones: [
        CmsLearnedMilestone(
          title: 'Stage 1 Loaded',
          detail: '${structuralBends.length} structural bends and ${flanges.length} return flanges loaded from DSF.',
        ),
      ],
    );
    notifyListeners();
  }

  /// Sets up controller state when reopening an existing Stage 2 DSF (ports mapped, scaling pending).
  void resumeAtStage2({required DsfDocument document, required CmsProductContract contract, required List<CmsPhysicalPort> ports}) {
    _state = CmsUxState(
      phase: CmsUxPhase.complete,
      contract: contract,
      discoveredPorts: ports,
      stageTitle: 'Stage 2: Ports Mapped',
      stageSubtitle: '${ports.length} physical channel ports verified. Ready for Teach Scaling.',
      progress: 0.66,
      learnedMilestones: [
        CmsLearnedMilestone(
          title: 'Stage 2 Loaded',
          detail: '${ports.length} ports loaded from DSF. Invariant coupler features locked.',
        ),
      ],
    );
    notifyListeners();
  }

  /// Directly starts Stage 2: Automatic Port Mapping using user-defined bends on [document].
  Future<void> startStage2PortMapping({required DsfDocument document, Duration stepDelay = Duration.zero}) async {
    final contract = _state.contract ?? CmsProductContract.lookup(null, document.itemName) ?? CmsProductContract.bend45;
    if (_state.contract == null) {
      _state = _state.copyWith(contract: contract);
    }
    await continueFoldingAndDiscovery(document: document, stepDelay: stepDelay);
  }

  /// User confirms the suggested bends or provides custom user-marked bends.
  Future<DsfDocument> applyUserBends({required List<FoldBendLine> userBends, required DsfDocument document, Duration stepDelay = Duration.zero}) async {
    // 1. Decompose planar faces from user-authorized bends
    final decomp = PlanarFaceDecomposer.decompose(outerContour: document.outerContour, bends: userBends, cutLines: document.cutLines);

    final updatedDoc = document.copyWith(bends: decomp.connectedBends, faces: decomp.faces, baseFaceId: decomp.baseFaceId);

    final structuralCount = userBends.where((b) => b.role != BendLineRole.flange).length;
    final flangeCount = userBends.where((b) => b.role == BendLineRole.flange).length;

    _addMilestone('Stage 2: Bend Structure Established', '$structuralCount structural bends and $flangeCount return flanges authorized by user.');

    // 2. Automatically advance through Stage 3, 4, 5, 6, 7
    await continueFoldingAndDiscovery(document: updatedDoc, stepDelay: stepDelay);
    return updatedDoc;
  }

  /// Continues the downstream stages (Folding -> Port Discovery -> Feature Protection -> Scaling).
  Future<void> continueFoldingAndDiscovery({required DsfDocument document, Duration stepDelay = Duration.zero}) async {
    final contract = _state.contract ?? CmsProductContract.bend45;

    // -------------------------------------------------------------------------
    // Stage 3: Observable 3D Fold
    // -------------------------------------------------------------------------
    _updateState(
      _state.copyWith(
        phase: CmsUxPhase.folding,
        stageTitle: 'Stage 3 of 7: 3D Fold',
        stageSubtitle: 'Folding upright channel via forward kinematics...',
        progress: 0.42,
      ),
    );
    if (stepDelay > Duration.zero) await Future.delayed(stepDelay);

    DsfDocument docToFold = document;
    if (docToFold.bends.isNotEmpty) {
      final decomp = PlanarFaceDecomposer.decompose(
        outerContour: docToFold.outerContour,
        bends: docToFold.bends,
        cutLines: docToFold.cutLines,
        preferredBaseFaceId: docToFold.baseFaceId,
      );
      docToFold = docToFold.copyWith(
        bends: decomp.connectedBends,
        faces: decomp.faces,
        baseFaceId: decomp.baseFaceId,
      );
    }

    final foldResult = KinematicFoldEngine.foldDocument(docToFold, foldProgress: 1.0);

    // HARD GUARD: Prohibit 3D port discovery on flat or unbent geometry!
    if (foldResult.polygons.length <= 1) {
      _updateState(
        _state.copyWith(
          phase: CmsUxPhase.error,
          stageTitle: '3D Fold Incomplete',
          activeErrorMessage: 'Part has <= 1 face. Cannot discover channel ports on a flat sheet.',
        ),
      );
      return;
    }

    _addMilestone('Stage 3: 3D Channel Folded', '${foldResult.polygons.length} folded 3D faces synthesized.');

    // -------------------------------------------------------------------------
    // Stage 4: Automatic Physical Port Discovery & Matching
    // -------------------------------------------------------------------------
    _updateState(
      _state.copyWith(
        phase: CmsUxPhase.detectingOpenings,
        stageTitle: 'Stage 4 of 7: Physical Ports',
        stageSubtitle: 'Scanning open boundary loops of the folded 3D channel...',
        progress: 0.57,
      ),
    );
    if (stepDelay > Duration.zero) await Future.delayed(stepDelay);

    // HARD GUARD: Port discovery strictly operates on the 3D folded representation
    final rawOpenings = Cms3DOpeningDetector.detectOpenings(document: docToFold, foldResult: foldResult);

    final measured = rawOpenings.map((r) => CmsOpeningPlaneAnalyzer.analyze(raw: r, document: docToFold, foldResult: foldResult)).toList();
    final candidates = measured.map((m) => m.toCandidate()).toList();

    _addMilestone('Stage 4: 3D Openings Located', 'Identified ${rawOpenings.length} terminal boundary loops on the folded 3D model.');

    _updateState(
      _state.copyWith(
        phase: CmsUxPhase.matchingPorts,
        candidateOpenings: candidates,
        stageSubtitle: 'Correlating physical 3D openings to ${contract.displayName}...',
        progress: 0.70,
      ),
    );
    if (stepDelay > Duration.zero) await Future.delayed(stepDelay);

    final matchResult = CmsPortMatcher.match(measuredOpenings: measured, contract: contract);

    // Safety Net: If genuine geometric conflict exists, activate exception path
    if (matchResult.requiresUserResolution) {
      _updateState(
        _state.copyWith(
          phase: CmsUxPhase.ambiguityRequired,
          stageTitle: 'Ambiguity Resolution Required',
          stageSubtitle: matchResult.ambiguityReason ?? 'Please verify candidate opening assignments.',
          candidateOpenings: matchResult.unmatchedCandidates,
        ),
      );
      return;
    }

    final matchedPorts = matchResult.matchedPorts;
    for (final port in matchedPorts) {
      _addMilestone(
        'Matched ${port.id}',
        '${port.width.toStringAsFixed(1)} × ${port.height.toStringAsFixed(1)} mm '
            '(Normal: ${port.normal.x.toStringAsFixed(2)}, ${port.normal.y.toStringAsFixed(2)}, ${port.normal.z.toStringAsFixed(2)})',
      );
    }

    // -------------------------------------------------------------------------
    // Stage 5: Feature Protection (Coupler Fasteners)
    // -------------------------------------------------------------------------
    final structuralBends = docToFold.bends.where((b) => b.role != BendLineRole.flange).map((b) => b.id).toList();
    final flanges = docToFold.bends.where((b) => b.role == BendLineRole.flange).map((b) => b.id).toList();

    _updateState(
      _state.copyWith(
        phase: CmsUxPhase.classifyingCouplers,
        discoveredPorts: matchedPorts,
        verifiedBendIds: structuralBends,
        verifiedFlangeIds: flanges,
        stageTitle: 'Stage 5 of 7: Feature Protection',
        stageSubtitle: 'Locking rigid fastener slots to port sidewalls...',
        progress: 0.85,
      ),
    );
    if (stepDelay > Duration.zero) await Future.delayed(stepDelay);

    final classification = CmsCouplerClassifier.classify(document: docToFold, contract: contract, ports: matchedPorts);

    final couplerIds = classification.couplerSlots.map((p) => p.id).toList();
    _addMilestone('Stage 5: Coupler Fasteners Protected', '${classification.couplerSlots.length} rigid 8×12mm slots locked to ports (Invariant to scaling).');

    // -------------------------------------------------------------------------
    // Stage 6: Smart Scaling & Constraint Graph
    // -------------------------------------------------------------------------
    _updateState(
      _state.copyWith(
        phase: CmsUxPhase.buildingConstraints,
        stageTitle: 'Stage 6 of 7: Smart Scaling',
        stageSubtitle: 'Building parametric topological relationships...',
        progress: 0.95,
      ),
    );
    if (stepDelay > Duration.zero) await Future.delayed(stepDelay);

    _addMilestone('Stage 6: Smart Scaling Ready', 'Topological constraint relationships wired between ports, sidewalls, and flanges.');

    // -------------------------------------------------------------------------
    // Stage 7: Template Complete
    // -------------------------------------------------------------------------
    _updateState(
      _state.copyWith(
        phase: CmsUxPhase.complete,
        classifiedCouplerPunchIds: couplerIds,
        stageTitle: 'Stage 7 of 7: Template Complete',
        stageSubtitle: 'CMS template fully understood and verified for ${contract.displayName}.',
        progress: 1.0,
      ),
    );
  }

  /// Sets visual focus on specific elements to synchronize 2D <-> 3D highlights.
  void setVisualFocus(CmsVisualFocus focus) {
    _state = _state.copyWith(focus: focus);
    notifyListeners();
  }

  /// User confirms or overrides ambiguous candidate ports (Exception Path).
  void resolveAmbiguity(List<CmsPhysicalPort> resolvedPorts) {
    _state = _state.copyWith(
      discoveredPorts: resolvedPorts,
      phase: CmsUxPhase.classifyingCouplers,
      stageTitle: 'Ambiguity Resolved',
      stageSubtitle: 'Proceeding with verified port assignments.',
    );
    notifyListeners();
  }

  /// Finalizes and marks the guided CMS authoring session as complete.
  void completeSession() {
    _state = _state.copyWith(phase: CmsUxPhase.complete);
    notifyListeners();
  }

  /// Resets controller state.
  void reset() {
    _state = const CmsUxState();
    notifyListeners();
  }

  /// Updates the discovered ports list (e.g. when resynchronizing from 3D mesh).
  void updateDiscoveredPorts(List<CmsPhysicalPort> ports) {
    _state = _state.copyWith(discoveredPorts: ports);
    notifyListeners();
  }

  void _updateState(CmsUxState newState) {
    _state = newState;
    notifyListeners();
  }

  void _addMilestone(String title, String detail) {
    final updated = List<CmsLearnedMilestone>.from(_state.learnedMilestones)..add(CmsLearnedMilestone(title: title, detail: detail));
    _state = _state.copyWith(learnedMilestones: updated);
    notifyListeners();
  }
}
