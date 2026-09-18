// =============================================================================
// cms_opening_plane_analyzer.dart
//
// Fits local opening planes, projects boundary loops, and measures true physical
// W x H dimensions and normal vectors per TRUFOLD_LEGACY_ISOLATION_CLEAN_CMS_ARCHITECTURE.md
// (Section 11).
// =============================================================================

import 'dart:math' as math;
import '../kinematic_fold_engine.dart';
import '../../models/cad_primitives.dart';
import '../../models/dsf_document.dart';
import '../../models/cms/cms_ux_state.dart';
import 'cms_3d_opening_detector.dart';

class CmsMeasuredOpening {
  final String openingId;
  final double width;
  final double height;
  final double flange;
  final CadPoint3D center;
  final CadPoint3D normal;
  final CadPoint3D widthDirection;
  final CadPoint3D heightDirection;
  final CadPoint3D floorP1;
  final CadPoint3D floorP2;
  final CadPoint2D flatP1;
  final CadPoint2D flatP2;
  final String floorFaceId;
  final List<String> sidewallFaceIds;
  final List<CadPoint3D> derivedMouthCorners;
  final CadPoint3D calloutAnchor;

  const CmsMeasuredOpening({
    required this.openingId,
    required this.width,
    required this.height,
    required this.flange,
    required this.center,
    required this.normal,
    required this.widthDirection,
    required this.heightDirection,
    required this.floorP1,
    required this.floorP2,
    required this.flatP1,
    required this.flatP2,
    required this.floorFaceId,
    required this.sidewallFaceIds,
    this.derivedMouthCorners = const [],
    this.calloutAnchor = const CadPoint3D(0, 0, 0),
  });

  CmsPortCandidate toCandidate({double matchScore = 1.0, String? matchedPortId}) {
    return CmsPortCandidate(
      candidateId: openingId,
      width: width,
      height: height,
      center: center,
      normal: normal,
      matchScore: matchScore,
      matchedPortId: matchedPortId,
      isReliefOrNotch: width < 15.0 || height < 15.0,
    );
  }
}

/// Analyzes raw 3D openings to calculate accurate physical opening dimensions.
class CmsOpeningPlaneAnalyzer {
  /// Measures true physical width (across floor mouth) and sidewall height.
  static CmsMeasuredOpening analyze({
    required CmsRaw3DOpening raw,
    required DsfDocument document,
    FoldedMeshResult? foldResult,
    double defaultHeight = 100.0,
    double defaultFlange = 15.0,
  }) {
    final p1 = raw.floorEdgeP1;
    final p2 = raw.floorEdgeP2;

    // 1. Measure opening width directly from floor edge length
    final dx = p2.x - p1.x;
    final dy = p2.y - p1.y;
    final dz = p2.z - p1.z;
    final measuredWidth = math.sqrt(dx * dx + dy * dy + dz * dz);

    // 2. Unit width direction vector
    final invW = measuredWidth > 1e-4 ? 1.0 / measuredWidth : 1.0;
    final widthDirection = CadPoint3D(dx * invW, dy * invW, dz * invW);

    // 3. Normal vector (outward horizontal)
    final normal = raw.outwardNormal;

    // 4. Vertical height direction (perpendicular to floor plane)
    const heightDirection = CadPoint3D(0, 0, 1);

    // 5. Measure height and find top lip Z from 3D folded mesh
    double measuredHeight = defaultHeight;
    double measuredFlange = defaultFlange;
    double? lipZ;

    if (foldResult != null && foldResult.polygons.isNotEmpty && raw.sidewallFaceIds.isNotEmpty) {
      for (final poly in foldResult.polygons) {
        if (raw.sidewallFaceIds.contains(poly.faceId)) {
          for (final v in poly.vertices) {
            if (lipZ == null || (v.z - p1.z).abs() > (lipZ - p1.z).abs()) {
              lipZ = v.z;
            }
          }
        }
      }
      if (lipZ != null && (lipZ - p1.z).abs() > 15.0) {
        measuredHeight = (lipZ - p1.z).abs();
      }
    }

    if (lipZ == null) {
      // Fallback: estimate height from flat face vertices
      if (raw.sidewallFaceIds.isNotEmpty) {
        double maxWallH = 0.0;
        for (final faceId in raw.sidewallFaceIds) {
          final face = document.faces.firstWhere(
            (f) => f.id == faceId,
            orElse: () => document.faces.first,
          );
          final h = _estimateFaceHeight(face.vertices);
          if (h > maxWallH) maxWallH = h;
        }
        if (maxWallH > 20.0) measuredHeight = maxWallH;
      }
      lipZ = p1.z + measuredHeight;
    }

    // 6. Derived 4 corners of the channel mouth [P1 (floor), P3 (lip), P4 (lip), P2 (floor)]
    final p3 = CadPoint3D(p1.x, p1.y, lipZ);
    final p4 = CadPoint3D(p2.x, p2.y, lipZ);
    final derivedMouthCorners = [p1, p3, p4, p2];

    // 7. True mouth centroid (midpoint of floor & top lip)
    final center = CadPoint3D(
      (p1.x + p2.x) / 2.0,
      (p1.y + p2.y) / 2.0,
      (p1.z + lipZ) / 2.0,
    );

    // 8. Callout anchor pinned directly on top rim mouth center
    final calloutAnchor = CadPoint3D(
      (p1.x + p2.x) / 2.0,
      (p1.y + p2.y) / 2.0,
      lipZ,
    );

    return CmsMeasuredOpening(
      openingId: raw.openingId,
      width: (measuredWidth * 10.0).roundToDouble() / 10.0,
      height: (measuredHeight * 10.0).roundToDouble() / 10.0,
      flange: measuredFlange,
      center: center,
      normal: normal,
      widthDirection: widthDirection,
      heightDirection: heightDirection,
      floorP1: p1,
      floorP2: p2,
      flatP1: raw.flatFloorEdgeP1,
      flatP2: raw.flatFloorEdgeP2,
      floorFaceId: raw.floorFaceId,
      sidewallFaceIds: raw.sidewallFaceIds,
      derivedMouthCorners: derivedMouthCorners,
      calloutAnchor: calloutAnchor,
    );
  }

  static double _estimateFaceHeight(List<CadPoint2D> vertices) {
    if (vertices.length < 3) return 0.0;
    double minX = vertices.first.x, maxX = vertices.first.x;
    double minY = vertices.first.y, maxY = vertices.first.y;

    for (final v in vertices) {
      if (v.x < minX) minX = v.x;
      if (v.x > maxX) maxX = v.x;
      if (v.y < minY) minY = v.y;
      if (v.y > maxY) maxY = v.y;
    }

    final spanX = maxX - minX;
    final spanY = maxY - minY;
    // In typical sidewalls, one dimension is length, the smaller is height
    return math.min(spanX, spanY);
  }
}
