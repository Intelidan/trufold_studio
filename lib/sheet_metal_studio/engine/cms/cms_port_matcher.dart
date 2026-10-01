// =============================================================================
// cms_port_matcher.dart
//
// Matches detected 3D physical openings to product contracts and user expectations
// per TRUFOLD_LEGACY_ISOLATION_CLEAN_CMS_ARCHITECTURE.md (Sections 11 & 19).
// =============================================================================

import 'dart:math' as math;
import '../../models/cad_primitives.dart';
import '../../models/cms/cms_physical_port.dart';
import '../../models/cms/cms_product_contract.dart';


import '../../models/cms/cms_ux_state.dart';
import 'cms_opening_plane_analyzer.dart';

/// Result of matching measured 3D openings against expected product contracts.
class CmsPortMatchResult {
  final List<CmsPhysicalPort> matchedPorts;
  final List<CmsPortCandidate> unmatchedCandidates;
  final bool isComplete;
  final bool requiresUserResolution;
  final String? ambiguityReason;
  final double overallConfidence;

  const CmsPortMatchResult({
    required this.matchedPorts,
    this.unmatchedCandidates = const [],
    required this.isComplete,
    required this.requiresUserResolution,
    this.ambiguityReason,
    this.overallConfidence = 1.0,
  });
}

/// Matches detected physical openings to expected catalog contracts.
class CmsPortMatcher {
  /// Matches a list of measured 3D openings to the specified product contract.
  static CmsPortMatchResult match({
    required List<CmsMeasuredOpening> measuredOpenings,
    required CmsProductContract contract,
    Map<String, ({double width, double height})>? expectedPortSpecs,
  }) {
    // Filter out obvious relief notches and non-port slots
    final validOpenings = measuredOpenings.where((m) {
      return m.width >= 20.0 && m.height >= 15.0;
    }).toList();

    // If candidate count does not match expected port count, flag ambiguity
    if (validOpenings.length != contract.expectedPortCount) {
      final candidates = validOpenings.map((o) => o.toCandidate()).toList();
      return CmsPortMatchResult(
        matchedPorts: const [],
        unmatchedCandidates: candidates,
        isComplete: false,
        requiresUserResolution: true,
        ambiguityReason: 'Detected ${validOpenings.length} physical openings, '
            'but expected ${contract.expectedPortCount} for ${contract.displayName}.',
        overallConfidence: 0.4,
      );
    }

    double openingAngle(CmsMeasuredOpening o) {
      double nx = o.normal.x;
      double ny = o.normal.y;
      if (nx.abs() < 1e-4) nx = 0.0;
      if (ny.abs() < 1e-4) ny = 0.0;
      // Normal West (-1, 0): math.atan2(0.0, -1.0) can return +pi or -pi depending on sign bit.
      // Normalize West to -math.pi so it consistently sorts first before North (-pi/2).
      if (nx < -0.5 && ny.abs() < 1e-3) {
        return -math.pi;
      }
      return math.atan2(ny, nx);
    }

    // Sort openings topologically (by primary axis or angle) for stable, deterministic ordering
    validOpenings.sort((a, b) {
      // Sort primarily by normal angle or position
      final angleA = openingAngle(a);
      final angleB = openingAngle(b);
      if ((angleA - angleB).abs() > 0.05) {
        return angleA.compareTo(angleB);
      }
      return a.center.x.compareTo(b.center.x);
    });

    final matchedPorts = <CmsPhysicalPort>[];
    double totalConfidence = 0.0;

    for (int i = 0; i < validOpenings.length; i++) {
      final opening = validOpenings[i];
      final portIndex = i + 1;
      final portId = 'PORT_$portIndex';

      // Check against expected dimension specs if provided
      double portConfidence = 1.0;
      if (expectedPortSpecs != null && expectedPortSpecs.containsKey(portId)) {
        final expected = expectedPortSpecs[portId]!;
        final dw = (opening.width - expected.width).abs();
        final dh = (opening.height - expected.height).abs();
        if (dw > contract.dimensionalToleranceMm || dh > contract.dimensionalToleranceMm) {
          portConfidence = math.max(0.2, 1.0 - (dw + dh) * 0.05);
        }
      }

      // Determine suggested role based on product rules
      CmsPortRole? suggestedRole;
      String? roleReason;
      if (contract.productType == 'bend') {
        suggestedRole = CmsPortRole.bidirectional;
        roleReason = 'Standard bend ports are physically symmetrical and bidirectional.';
      } else if (contract.productType == 'tee') {
        if (contract.variationName.contains('equal')) {
          suggestedRole = CmsPortRole.unassigned;
          roleReason = 'Equal tee ports are geometrically symmetric; user assigns flow role if needed.';
        } else {
          // Check if this opening has the largest width
          final isLargest = validOpenings.every((other) => opening.width >= other.width - 1.0);
          if (isLargest) {
            suggestedRole = CmsPortRole.main;
            roleReason = 'Largest width opening inferred as candidate for Main/Inlet.';
          } else {
            suggestedRole = CmsPortRole.branch;
            roleReason = 'Branch port with smaller cross-section.';
          }
        }
      } else if (contract.productType == 'cross') {
        suggestedRole = CmsPortRole.unassigned;
        roleReason = 'Symmetric 4-way cross ports remain neutral until user assignment.';
      }

      matchedPorts.add(CmsPhysicalPort(
        id: portId,
        index: portIndex,
        width: opening.width,
        height: opening.height,
        flange: opening.flange,
        center: opening.center,
        flatCenter: CadPoint2D(
          (opening.flatP1.x + opening.flatP2.x) * 0.5,
          (opening.flatP1.y + opening.flatP2.y) * 0.5,
        ),
        normal: opening.normal,
        widthDirection: opening.widthDirection,
        heightDirection: opening.heightDirection,
        hostFaceIds: [opening.floorFaceId, ...opening.sidewallFaceIds],
        boundaryLoopId: opening.openingId,
        floorP1: opening.floorP1,
        floorP2: opening.floorP2,
        flatP1: opening.flatP1,
        flatP2: opening.flatP2,
        derivedMouthCorners: opening.derivedMouthCorners,
        calloutAnchor: opening.calloutAnchor,
        confidence: portConfidence,
        detectionSource: PortDetectionSource.foldedTopology,
        suggestedRole: suggestedRole,
        suggestionReason: roleReason,
      ));

      totalConfidence += portConfidence;
    }

    final avgConfidence = matchedPorts.isNotEmpty
        ? totalConfidence / matchedPorts.length
        : 0.0;

    return CmsPortMatchResult(
      matchedPorts: matchedPorts,
      unmatchedCandidates: const [],
      isComplete: true,
      requiresUserResolution: avgConfidence < 0.75,
      overallConfidence: avgConfidence,
    );
  }
}
