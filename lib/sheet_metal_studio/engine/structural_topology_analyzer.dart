// =============================================================================
// structural_topology_analyzer.dart
//
// Structural & 3D Folded Topology Analyzer for Sheet Metal Studio
// per INTELLIGENT_BEND_LINES_TEMPLATE_WALKTHROUGH.md.
//
// Core Principle:
// Reuses the existing DSF bend calculations and KinematicFoldEngine 3D topology
// as the ground truth to reliably derive:
// 1. Planar face roles: Floor Web, Sidewalls, Flanges/Hems, Miters
// 2. 3D Open Channel Mouths -> Physical Ports (Width W, Height H, Outward Normal)
// 3. Coupler Mounting Holes vs Perforation Patterns
// 4. Product Variation Contract matching and high-confidence classification
// =============================================================================

import 'dart:math' as math;
import '../models/cad_primitives.dart';
import '../models/cnc_punch_primitive.dart';
import '../models/dsf_document.dart';
import '../models/fold_bend_line.dart';
import '../models/planar_sheet_face.dart';
import '../models/template_parameter_definition.dart';
import 'kinematic_fold_engine.dart';
import 'port_inference_engine.dart';
import 'fitting_port_annotation_engine.dart';

/// Semantic role of a planar face in a sheet metal fitting
enum FaceSemanticRole {
  floor,
  sidewall,
  returnFlange,
  miter,
  couplerTab,
  unknown;

  String get displayName {
    switch (this) {
      case FaceSemanticRole.floor:
        return 'Floor Web';
      case FaceSemanticRole.sidewall:
        return 'Sidewall';
      case FaceSemanticRole.returnFlange:
        return 'Return Flange';
      case FaceSemanticRole.miter:
        return 'Miter Transition';
      case FaceSemanticRole.couplerTab:
        return 'Coupler Tab';
      case FaceSemanticRole.unknown:
        return 'General Panel';
    }
  }
}

/// Comprehensive topological analysis result
class StructuralTopologyResult {
  final PlanarSheetFace? floorFace;
  final List<PlanarSheetFace> sidewallFaces;
  final List<PlanarSheetFace> flangeFaces;
  final List<PlanarSheetFace> miterFaces;
  final Map<String, FaceSemanticRole> faceRoles;
  final List<PortInferenceResult> detectedPorts;
  final List<CncPunchPrimitive> classifiedPunches;
  final double detectedWidth;
  final double detectedHeight;
  final double detectedFlange;
  final double confidence;
  final String statusMessage;
  final ProductVariationContract? matchedContract;

  const StructuralTopologyResult({
    this.floorFace,
    this.sidewallFaces = const [],
    this.flangeFaces = const [],
    this.miterFaces = const [],
    this.faceRoles = const {},
    this.detectedPorts = const [],
    this.classifiedPunches = const [],
    this.detectedWidth = 0.0,
    this.detectedHeight = 0.0,
    this.detectedFlange = 0.0,
    this.confidence = 1.0,
    this.statusMessage = '',
    this.matchedContract,
  });

  bool get isHighConfidence => confidence >= 0.85;

  List<CncPunchPrimitive> get couplerPunches =>
      classifiedPunches.where((p) => p.isCoupler).toList();

  List<CncPunchPrimitive> get perforationPunches =>
      classifiedPunches.where((p) => p.isPerforation).toList();
}

class StructuralTopologyAnalyzer {
  /// Analyzes a [DsfDocument] using its bend lines and 3D folded geometry
  /// to identify semantic ports, branches, flanges, and coupler hole clusters.
  static StructuralTopologyResult analyze(
    DsfDocument document, {
    String? productType,
    String? variantName,
    ProductVariationContract? contractOverride,
  }) {
    // 1. Resolve product contract if specified
    final pType = productType ?? document.productType;
    final vName = variantName ?? (document.metadata['fittingVariant'] as String? ?? '');
    final contract = contractOverride ?? ProductVariationContract.lookup(pType, vName);

    // 2. Perform 3D forward-kinematics fold
    final foldResult = KinematicFoldEngine.foldDocument(document, foldProgress: 1.0);

    // 3. Classify planar faces using bend topology
    final faceRoles = <String, FaceSemanticRole>{};
    final sidewallFaces = <PlanarSheetFace>[];
    final flangeFaces = <PlanarSheetFace>[];
    final miterFaces = <PlanarSheetFace>[];

    // Find the floor face (anchor or largest horizontal base)
    PlanarSheetFace? floorFace = _identifyFloorFace(document, foldResult);

    if (floorFace != null) {
      faceRoles[floorFace.id] = FaceSemanticRole.floor;
    }

    // Traverse bends connected to the floor face to classify children
    for (final bend in document.bends) {
      final isConnectedToFloor = floorFace != null &&
          (bend.parentFaceId == floorFace.id || bend.childFaceId == floorFace.id);

      final otherFaceId = floorFace != null
          ? (bend.parentFaceId == floorFace.id ? bend.childFaceId : bend.parentFaceId)
          : null;

      final otherFace = document.faces.firstWhere(
        (f) => f.id == otherFaceId,
        orElse: () => PlanarSheetFace(id: otherFaceId ?? '', vertices: const []),
      );

      if (otherFace.vertices.isEmpty) continue;

      if (bend.role == BendLineRole.flange) {
        faceRoles[otherFace.id] = FaceSemanticRole.returnFlange;
        flangeFaces.add(otherFace);
      } else if (isConnectedToFloor) {
        if ((bend.targetAngleDeg - 90.0).abs() < 10.0) {
          faceRoles[otherFace.id] = FaceSemanticRole.sidewall;
          sidewallFaces.add(otherFace);
        } else {
          faceRoles[otherFace.id] = FaceSemanticRole.miter;
          miterFaces.add(otherFace);
        }
      } else {
        if ((bend.targetAngleDeg - 90.0).abs() < 10.0) {
          faceRoles[otherFace.id] = FaceSemanticRole.sidewall;
          sidewallFaces.add(otherFace);
        } else {
          faceRoles[otherFace.id] = FaceSemanticRole.miter;
          miterFaces.add(otherFace);
        }
      }
    }

    // Fill in any remaining unclassified faces
    for (final face in document.faces) {
      faceRoles.putIfAbsent(face.id, () => FaceSemanticRole.unknown);
    }

    // 4. Discover physical ports from 3D open channel mouths
    final detectedPorts = _discoverPortsFromTopology(
      document: document,
      floorFace: floorFace,
      sidewallFaces: sidewallFaces,
      flangeFaces: flangeFaces,
    );

    // 5. Measure nominal dimensions (Width, Height, Flange)
    double detectedWidth = 0.0;
    double detectedHeight = 0.0;
    double detectedFlange = 0.0;

    if (detectedPorts.isNotEmpty) {
      detectedWidth = detectedPorts.first.inferredWidth;
      detectedHeight = detectedPorts.first.inferredHeightA;
    }

    // Measure flange height from flange bends if available
    for (final bend in document.bends) {
      if (bend.role == BendLineRole.flange) {
        // Find distance to boundary
        final fFace = flangeFaces.firstWhere((f) => f.id == bend.childFaceId || f.id == bend.parentFaceId,
            orElse: () => PlanarSheetFace(id: '', vertices: const []));
        if (fFace.vertices.isNotEmpty) {
          final maxDist = _maxPerpendicularDistance(fFace.vertices, bend.p1, bend.p2);
          if (maxDist > 0.0) {
            detectedFlange = math.max(detectedFlange, maxDist);
          }
        }
      }
    }
    if (detectedFlange <= 0.0) {
      detectedFlange = (document.metadata['fittingFlangeMm'] as num?)?.toDouble() ?? 10.0;
    }

    // 6. Classify punches: Coupler Mounting Holes vs Perforations
    final classifiedPunches = _classifyPunches(
      document: document,
      detectedPorts: detectedPorts,
      floorFace: floorFace,
      sidewallFaces: sidewallFaces,
    );

    // 7. Calculate confidence against contract
    double confidence = 1.0;
    final notes = <String>[];

    if (contract != null) {
      if (detectedPorts.length == contract.expectedPortCount) {
        notes.add('Port count matches contract (${contract.expectedPortCount})');
      } else {
        confidence -= 0.25;
        notes.add('Port count mismatch: found ${detectedPorts.length}, expected ${contract.expectedPortCount}');
      }

      final couplerCount = classifiedPunches.where((p) => p.isCoupler).length;
      final expectedCouplers = contract.expectedCouplerSlotsPerPort * contract.expectedPortCount;
      if (couplerCount == expectedCouplers) {
        notes.add('Coupler count matches contract ($couplerCount slots)');
      } else if (couplerCount > 0) {
        notes.add('Found $couplerCount coupler slots (expected $expectedCouplers)');
      }
    } else {
      notes.add('Topological analysis completed without contract override');
    }

    return StructuralTopologyResult(
      floorFace: floorFace,
      sidewallFaces: sidewallFaces,
      flangeFaces: flangeFaces,
      miterFaces: miterFaces,
      faceRoles: faceRoles,
      detectedPorts: detectedPorts,
      classifiedPunches: classifiedPunches,
      detectedWidth: detectedWidth,
      detectedHeight: detectedHeight,
      detectedFlange: detectedFlange,
      confidence: confidence.clamp(0.1, 1.0),
      statusMessage: notes.join(' | '),
      matchedContract: contract,
    );
  }

  /// Identifies the Floor Web face from document faces and 3D orientation
  static PlanarSheetFace? _identifyFloorFace(
    DsfDocument document,
    FoldedMeshResult foldResult,
  ) {
    if (document.faces.isEmpty) return null;

    // A. Largest face whose 3D normal is vertical (|normal.z| > 0.8)
    PlanarSheetFace? bestFace;
    double maxArea = -1.0;

    for (final poly in foldResult.polygons) {
      if (poly.normal.z.abs() > 0.8) {
        final face = document.faces.firstWhere(
          (f) => f.id == poly.faceId,
          orElse: () => PlanarSheetFace(id: poly.faceId, vertices: const []),
        );
        final area = face.areaMm2;
        if (area > maxArea) {
          maxArea = area;
          bestFace = face;
        }
      }
    }

    if (bestFace != null && maxArea > 100.0) {
      return bestFace;
    }

    // B. Explicit base anchor
    try {
      final anchor = document.faces.firstWhere((f) => f.id == document.baseFaceId || f.isBaseAnchor);
      return anchor;
    } catch (_) {}

    return bestFace ?? (document.faces.isNotEmpty ? document.faces.first : null);
  }

  /// Discovers physical ports from open channel mouths
  static List<PortInferenceResult> _discoverPortsFromTopology({
    required DsfDocument document,
    required PlanarSheetFace? floorFace,
    required List<PlanarSheetFace> sidewallFaces,
    required List<PlanarSheetFace> flangeFaces,
  }) {
    final results = <PortInferenceResult>[];
    final contour = document.outerContour;
    if (contour.length < 3) return results;

    // Check if DSF already contains explicit ports
    final dsfPorts = (document.metadata['ports'] as List<dynamic>?) ?? [];
    if (dsfPorts.isNotEmpty) {
      for (int i = 0; i < dsfPorts.length; i++) {
        final p = dsfPorts[i] as Map<String, dynamic>;
        final pId = p['id'] as String? ?? 'port${i + 1}';
        final edgeP1 = p['edgeP1'] as List<dynamic>?;
        final edgeP2 = p['edgeP2'] as List<dynamic>?;
        final normalArr = p['normal'] as List<dynamic>?;

        CadPoint2D? pt1, pt2, norm;
        if (edgeP1 != null && edgeP1.length >= 2) {
          pt1 = CadPoint2D((edgeP1[0] as num).toDouble(), (edgeP1[1] as num).toDouble());
        }
        if (edgeP2 != null && edgeP2.length >= 2) {
          pt2 = CadPoint2D((edgeP2[0] as num).toDouble(), (edgeP2[1] as num).toDouble());
        }
        if (normalArr != null && normalArr.length >= 2) {
          norm = CadPoint2D((normalArr[0] as num).toDouble(), (normalArr[1] as num).toDouble());
        }

        if (pt1 != null && pt2 != null) {
          final opening = CadLineSegment(id: 'port_${i + 1}_edge', p1: pt1, p2: pt2);
          final w = (p['width'] as num?)?.toDouble() ?? pt1.distanceTo(pt2);
          final h = (p['height'] as num?)?.toDouble() ?? 100.0;
          final sideStr = p['side'] as String? ?? 'south';
          final portSide = PortSide.values.firstWhere(
            (s) => s.name.toLowerCase() == sideStr.toLowerCase(),
            orElse: () => PortSide.south,
          );

          results.add(PortInferenceResult(
            portId: pId,
            openingEdge: opening,
            inferredWidth: w,
            inferredHeightA: h,
            inferredHeightB: h,
            normal: norm ?? const CadPoint2D(0, -1),
            outwardNormalAngleRad: norm != null ? math.atan2(norm.y, norm.x) : -math.pi / 2,
            inferredSide: portSide,
            confidence: 1.0,
            inferenceNotes: 'Loaded directly from verified DSF port definition',
          ));
        }
      }
      if (results.isNotEmpty) return results;
    }

    // Auto-discover from outerContour opening edges
    final autoDetected = PortInferenceEngine.autoDetectAllPorts(document);
    return autoDetected;
  }

  /// Classifies punches into Coupler Mounting Holes vs Regular Perforations
  static List<CncPunchPrimitive> _classifyPunches({
    required DsfDocument document,
    required List<PortInferenceResult> detectedPorts,
    required PlanarSheetFace? floorFace,
    required List<PlanarSheetFace> sidewallFaces,
  }) {
    final updated = <CncPunchPrimitive>[];

    for (final punch in document.allPunches) {
      // 1. Check if hosted on or close to a port opening edge (coupler zone)
      String? matchedPortId;
      double minPortDist = double.infinity;

      for (final port in detectedPorts) {
        final dist = _distancePointToSegment(punch.center, port.openingEdge.p1, port.openingEdge.p2);
        final maxCouplerReach = math.max(port.inferredHeightA, port.inferredHeightB) + 40.0;

        if (dist <= maxCouplerReach && dist < minPortDist) {
          minPortDist = dist;
          matchedPortId = port.portId;
        }
      }

      // 2. Classify role
      CncPunchRole role = punch.role;
      if (role == CncPunchRole.general) {
        if (matchedPortId != null && minPortDist < 160.0) {
          role = CncPunchRole.coupler;
        } else if (floorFace != null && isPointInsidePolygon(punch.center, floorFace.vertices)) {
          role = CncPunchRole.perforation;
        } else {
          // Slots or clearance holes on sidewall/tab/flange faces are coupler fastener features
          if (punch.isSlot || punch.diameterMm <= 12.0) {
            role = CncPunchRole.coupler;
          }
        }
      }

      if (role == CncPunchRole.coupler && matchedPortId == null && detectedPorts.isNotEmpty) {
        // Associate with nearest detected port
        double closestD = double.infinity;
        for (final port in detectedPorts) {
          final d = _distancePointToSegment(punch.center, port.openingEdge.p1, port.openingEdge.p2);
          if (d < closestD) {
            closestD = d;
            matchedPortId = port.portId;
          }
        }
      }

      updated.add(punch.copyWith(
        role: role,
        associatedPortId: matchedPortId,
      ));
    }

    return updated;
  }

  static double _distancePointToSegment(CadPoint2D pt, CadPoint2D p1, CadPoint2D p2) {
    final dx = p2.x - p1.x;
    final dy = p2.y - p1.y;
    final lenSq = dx * dx + dy * dy;
    if (lenSq < 1e-9) return pt.distanceTo(p1);

    final t = (((pt.x - p1.x) * dx + (pt.y - p1.y) * dy) / lenSq).clamp(0.0, 1.0);
    final proj = CadPoint2D(p1.x + t * dx, p1.y + t * dy);
    return pt.distanceTo(proj);
  }

  static double _maxPerpendicularDistance(List<CadPoint2D> vertices, CadPoint2D p1, CadPoint2D p2) {
    final dx = p2.x - p1.x;
    final dy = p2.y - p1.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-6) return 0.0;

    double maxD = 0.0;
    for (final v in vertices) {
      final d = ((v.x - p1.x) * dy - (v.y - p1.y) * dx).abs() / len;
      if (d > maxD) maxD = d;
    }
    return maxD;
  }

  static bool isPointInsidePolygon(CadPoint2D point, List<CadPoint2D> polygon) {
    if (polygon.length < 3) return false;
    bool inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      if (((polygon[i].y > point.y) != (polygon[j].y > point.y)) &&
          (point.x <
              (polygon[j].x - polygon[i].x) *
                      (point.y - polygon[i].y) /
                      (polygon[j].y - polygon[i].y) +
                  polygon[i].x)) {
        inside = !inside;
      }
    }
    return inside;
  }
}
