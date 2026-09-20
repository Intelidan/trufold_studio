// =============================================================================
// cms_coupler_classifier.dart
//
// Classifies sidewall fastener punches, distinguishing rigid coupler slots from
// ventilating/mounting perforations per TRUFOLD_LEGACY_ISOLATION_CLEAN_CMS_ARCHITECTURE.md
// (Sections 11 & 21).
// =============================================================================

import 'dart:math' as math;
import '../../models/cad_primitives.dart';
import '../../models/cnc_punch_primitive.dart';
import '../../models/dsf_document.dart';
import '../../models/cms/cms_physical_port.dart';
import '../../models/cms/cms_product_contract.dart';

/// Semantic classification of a CNC punch.
class CmsClassifiedPunch {
  final CncPunchPrimitive punch;
  final bool isCouplerSlot;
  final bool isPerforation;
  final String? associatedPortId;
  final String? hostFaceId;
  final CadPoint2D rigidOffsetFromPort;

  const CmsClassifiedPunch({
    required this.punch,
    required this.isCouplerSlot,
    required this.isPerforation,
    this.associatedPortId,
    this.hostFaceId,
    this.rigidOffsetFromPort = const CadPoint2D(0, 0),
  });
}

/// Result of classifying all punches within a sheet-metal document.
class CmsCouplerClassificationResult {
  final List<CmsClassifiedPunch> classifiedPunches;
  final List<CncPunchPrimitive> couplerSlots;
  final List<CncPunchPrimitive> perforations;
  final Map<String, List<CncPunchPrimitive>> couplerSlotsByPort;
  final bool matchesContract;
  final double confidence;

  const CmsCouplerClassificationResult({
    required this.classifiedPunches,
    required this.couplerSlots,
    required this.perforations,
    required this.couplerSlotsByPort,
    required this.matchesContract,
    required this.confidence,
  });
}

/// Identifies coupler mounting slots and locks their geometry as rigid invariants.
class CmsCouplerClassifier {
  /// Classifies punches in [document] according to [contract] and [ports].
  static CmsCouplerClassificationResult classify({
    required DsfDocument document,
    required CmsProductContract contract,
    List<CmsPhysicalPort> ports = const [],
  }) {
    final allPunches = document.punches;
    final classified = <CmsClassifiedPunch>[];
    final couplers = <CncPunchPrimitive>[];
    final perfs = <CncPunchPrimitive>[];
    final byPort = <String, List<CncPunchPrimitive>>{};

    for (final port in ports) {
      byPort[port.id] = [];
    }

    for (final p in allPunches) {
      // 1. Explicit semantic role or COUPLER layer takes highest precedence
      final isExplicitCoupler = p.role == CncPunchRole.coupler ||
          p.layer.toUpperCase() == 'COUPLER';

      // 2. Automatic candidate heuristic:
      // Standard cable tray / trunking obround slots typically have:
      // Width: 6 to 11 mm (nominally 8-9mm)
      // Length: 10 to 35 mm (nominally 12, 16, 20, 25, 30mm)
      final isSlotShape = p.isSlot ||
          p.type == PunchType.obroundSlot ||
          p.type == PunchType.rectangle;
      final isStandardSlotDim = p.widthMm >= 5.5 &&
          p.widthMm <= 11.5 &&
          p.lengthMm >= 9.5 &&
          p.lengthMm <= 36.0;

      final isCouplerCandidate = isExplicitCoupler || (isSlotShape && isStandardSlotDim);

      if (isCouplerCandidate) {
        // Associate with closest physical port
        String? closestPortId;
        double minDist = double.infinity;

        for (final port in ports) {
          final dist = _distanceToPort(p.center, port);
          if (dist < minDist) {
            minDist = dist;
            closestPortId = port.id;
          }
        }

        // Must be within reasonable distance (e.g. 180mm) to opening mouth
        final isValidCoupler = minDist < 180.0 || ports.isEmpty;
        if (isValidCoupler) {
          final markedCoupler = p.copyWith(
            role: CncPunchRole.coupler,
            associatedPortId: closestPortId,
          );
          couplers.add(markedCoupler);
          if (closestPortId != null) {
            byPort[closestPortId]?.add(markedCoupler);
          }


          classified.add(CmsClassifiedPunch(
            punch: markedCoupler,
            isCouplerSlot: true,
            isPerforation: false,
            associatedPortId: closestPortId,
          ));
          continue;
        }
      }

      // Otherwise treat as perforation / general punch
      final markedPerf = p.copyWith(role: CncPunchRole.perforation);
      perfs.add(markedPerf);
      classified.add(CmsClassifiedPunch(
        punch: markedPerf,
        isCouplerSlot: false,
        isPerforation: true,
      ));
    }

    final expectedTotal = contract.totalExpectedCouplerSlots;
    final matchesContract = couplers.length == expectedTotal || expectedTotal == 0;
    final confidence = matchesContract ? 1.0 : (couplers.isNotEmpty ? 0.8 : 0.5);

    return CmsCouplerClassificationResult(
      classifiedPunches: classified,
      couplerSlots: couplers,
      perforations: perfs,
      couplerSlotsByPort: byPort,
      matchesContract: matchesContract,
      confidence: confidence,
    );
  }

  static double _distanceToPort(CadPoint2D punchPt, CmsPhysicalPort port) {
    final dx = punchPt.x - port.flatCenter.x;
    final dy = punchPt.y - port.flatCenter.y;
    return math.sqrt(dx * dx + dy * dy);
  }
}

