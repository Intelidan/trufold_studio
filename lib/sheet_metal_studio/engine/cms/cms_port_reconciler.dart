// =============================================================================
// cms_port_reconciler.dart
//
// Maintains stable physical port identity across parametric scaling and re-folding
// operations per TRUFOLD_LEGACY_ISOLATION_CLEAN_CMS_ARCHITECTURE.md (Sections 11 & 12).
// =============================================================================

import '../../models/cms/cms_physical_port.dart';
import 'cms_opening_plane_analyzer.dart';


/// Reconciles newly detected physical openings with previously established ports
/// so that port identities (PORT_1, PORT_2) remain rock-solid throughout scaling.
class CmsPortReconciler {
  /// Reconciles [previousPorts] with [newlyMeasured] openings.
  static List<CmsPhysicalPort> reconcile({
    required List<CmsPhysicalPort> previousPorts,
    required List<CmsMeasuredOpening> newlyMeasured,
  }) {
    if (previousPorts.isEmpty) {
      // No previous ports: synthesize ports in sequential order
      return newlyMeasured.asMap().entries.map((entry) {
        final idx = entry.key + 1;
        final m = entry.value;
        return CmsPhysicalPort(
          id: 'PORT_$idx',
          index: idx,
          width: m.width,
          height: m.height,
          flange: m.flange,
          center: m.center,
          normal: m.normal,
          widthDirection: m.widthDirection,
          heightDirection: m.heightDirection,
          hostFaceIds: [m.floorFaceId, ...m.sidewallFaceIds],
          boundaryLoopId: m.openingId,
          confidence: 1.0,
          detectionSource: PortDetectionSource.foldedTopology,
        );
      }).toList();
    }

    final reconciled = <CmsPhysicalPort>[];
    final remainingOpenings = List<CmsMeasuredOpening>.from(newlyMeasured);

    for (final oldPort in previousPorts) {
      if (remainingOpenings.isEmpty) break;

      // Find the best matching opening based on normal alignment and host face overlap
      int bestIndex = -1;
      double bestScore = -1.0;

      for (int i = 0; i < remainingOpenings.length; i++) {
        final cand = remainingOpenings[i];

        // 1. Normal alignment: dot product
        final normalDot = oldPort.normal.x * cand.normal.x +
            oldPort.normal.y * cand.normal.y +
            oldPort.normal.z * cand.normal.z;

        // 2. Host face match bonus
        double faceBonus = 0.0;
        if (oldPort.hostFaceIds.contains(cand.floorFaceId)) {
          faceBonus += 0.5;
        }

        final score = normalDot + faceBonus;
        if (score > bestScore) {
          bestScore = score;
          bestIndex = i;
        }
      }

      if (bestIndex != -1 && bestScore > 0.5) {
        final matched = remainingOpenings.removeAt(bestIndex);
        reconciled.add(oldPort.copyWith(
          width: matched.width,
          height: matched.height,
          flange: matched.flange,
          center: matched.center,
          normal: matched.normal,
          widthDirection: matched.widthDirection,
          heightDirection: matched.heightDirection,
          hostFaceIds: [matched.floorFaceId, ...matched.sidewallFaceIds],
          boundaryLoopId: matched.openingId,
          confidence: 1.0,
        ));
      } else {
        // Retain previous port if no clear match was found
        reconciled.add(oldPort);
      }
    }

    // Append any leftover new openings that didn't match existing ports
    int nextIdx = previousPorts.length + 1;
    for (final leftover in remainingOpenings) {
      reconciled.add(CmsPhysicalPort(
        id: 'PORT_$nextIdx',
        index: nextIdx,
        width: leftover.width,
        height: leftover.height,
        flange: leftover.flange,
        center: leftover.center,
        normal: leftover.normal,
        widthDirection: leftover.widthDirection,
        heightDirection: leftover.heightDirection,
        hostFaceIds: [leftover.floorFaceId, ...leftover.sidewallFaceIds],
        boundaryLoopId: leftover.openingId,
        confidence: 0.8,
        detectionSource: PortDetectionSource.foldedTopology,
      ));
      nextIdx++;
    }

    return reconciled;
  }
}
