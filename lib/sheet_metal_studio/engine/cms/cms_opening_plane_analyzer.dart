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
import 'cms_scaling_controller.dart';

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
    double? fallbackHeight,
  }) {
    final p1 = raw.floorEdgeP1;
    final p2 = raw.floorEdgeP2;

    final docType = '${document.productType} ${document.itemName}'.toLowerCase();
    final isReducer = docType.contains('reducer') || CmsScalingController.isReducerGeometry(document);
    final isOutsideRiser = !isReducer && docType.contains('outside') && (docType.contains('riser') || docType.contains('rise'));
    final isInsideRiser = !isReducer && ((docType.contains('inside') && (docType.contains('riser') || docType.contains('rise'))) ||
        CmsScalingController.isInsideRiserGeometry(document));
    final isTee = docType.contains('tee');

    // 1. Measure opening width directly from floor edge length
    final dx = p2.x - p1.x;
    final dy = p2.y - p1.y;
    final dz = p2.z - p1.z;
    final measuredWidth = math.sqrt(dx * dx + dy * dy + dz * dz);

    // 2. Unit width direction vector
    final invW = measuredWidth > 1e-4 ? 1.0 / measuredWidth : 1.0;
    final widthDirection = CadPoint3D(dx * invW, dy * invW, dz * invW);

    // 3. Normal vector (outward 3D)
    final normal = raw.outwardNormal;

    // 4. Vertical height direction (perpendicular to floor plane and edge)
    var hx = normal.y * widthDirection.z - normal.z * widthDirection.y;
    var hy = normal.z * widthDirection.x - normal.x * widthDirection.z;
    var hz = normal.x * widthDirection.y - normal.y * widthDirection.x;
    final hLen = math.sqrt(hx * hx + hy * hy + hz * hz);
    if (hLen > 1e-4) {
      hx /= hLen;
      hy /= hLen;
      hz /= hLen;
    }

    // Determine the true height direction towards the standing channel walls.
    // 1st Priority: Check projection of 3D sidewall vertices in foldResult.
    bool orientedBySidewalls = false;
    if (foldResult != null && foldResult.polygons.isNotEmpty && raw.sidewallFaceIds.isNotEmpty) {
      double dotSum = 0.0;
      int count = 0;
      for (final poly in foldResult.polygons) {
        if (raw.sidewallFaceIds.contains(poly.faceId)) {
          for (final v in poly.vertices) {
            final distNormal = ((v.x - p1.x) * normal.x +
                                (v.y - p1.y) * normal.y +
                                (v.z - p1.z) * normal.z).abs();
            if (distNormal > 10.0) continue;
            final proj = (v.x - p1.x) * hx + (v.y - p1.y) * hy + (v.z - p1.z) * hz;
            if (proj.abs() > 2.0) {
              dotSum += proj;
              count++;
            }
          }
        }
      }
      if (count > 0 && dotSum.abs() > 1e-3) {
        if (dotSum < 0) {
          hx = -hx;
          hy = -hy;
          hz = -hz;
        }
        orientedBySidewalls = true;
      }
    }

    // 2nd Priority: Check floor face normal in 3D (walls fold toward the floor face normal).
    if (!orientedBySidewalls && foldResult != null && foldResult.polygons.isNotEmpty) {
      final floorPoly = foldResult.polygons.where((p) => p.faceId == raw.floorFaceId).firstOrNull;
      if (floorPoly != null) {
        final floorNorm = floorPoly.normal;
        final align = hx * floorNorm.x + hy * floorNorm.y + hz * floorNorm.z;
        if (align.abs() > 0.1) {
          if (align < 0) {
            hx = -hx;
            hy = -hy;
            hz = -hz;
          }
          orientedBySidewalls = true;
        }
      }
    }

    // 3rd Priority / Fallback: If no mesh available, default to +Z
    if (!orientedBySidewalls && hz < -1e-4) {
      hx = -hx;
      hy = -hy;
      hz = -hz;
    }
    final heightDirection = CadPoint3D(hx, hy, hz);

    // 5. Measure height and find top lip from 3D folded mesh
    // Determine nominal height from parameters or file name if available
    double? nominalH = fallbackHeight ?? (document.parameters['height'] as num?)?.toDouble();
    if (isReducer) {
      final floorFace = document.faces.firstWhere((f) => f.id == raw.floorFaceId, orElse: () => document.faces.first);
      final yMid = (floorFace.vertices.map((v) => v.y).reduce(math.min) + floorFace.vertices.map((v) => v.y).reduce(math.max)) / 2.0;
      final isPort1 = (raw.flatFloorEdgeP1.y + raw.flatFloorEdgeP2.y) / 2.0 < yMid;
      nominalH = isPort1
          ? ((document.parameters['port1_height'] as num?)?.toDouble() ?? (document.parameters['height'] as num?)?.toDouble())
          : ((document.parameters['port2_height'] as num?)?.toDouble());

      if (nominalH == null || nominalH <= 15.0) {
        final fullMatch = RegExp(r'(\d+)\s*[xX]\s*(\d+)\s*[xX]\s*(\d+)\s*[xX]\s*(\d+)').firstMatch('${document.itemName} ${document.productType}');
        if (fullMatch != null) {
          nominalH = isPort1 ? double.tryParse(fullMatch.group(2)!) : double.tryParse(fullMatch.group(4)!);
        } else {
          final simpleMatch = RegExp(r'(\d+)\s*[xX]\s*(\d+)').firstMatch('${document.itemName} ${document.productType}');
          if (simpleMatch != null) {
            nominalH = isPort1 ? double.tryParse(simpleMatch.group(2)!) : (double.tryParse(simpleMatch.group(2)!) ?? 100.0) / 2.0;
          }
        }
      }
      nominalH ??= isPort1 ? 100.0 : 50.0;
    } else if (isTee) {
      if (normal.x < -0.5) {
        nominalH = (document.parameters['port1_height'] as num?)?.toDouble();
      } else if (normal.x > 0.5) {
        nominalH = (document.parameters['port2_height'] as num?)?.toDouble();
      } else {
        nominalH = (document.parameters['port3_height'] as num?)?.toDouble();
      }
      nominalH ??= (document.parameters['height'] as num?)?.toDouble();
    } else if (nominalH == null || nominalH <= 15.0) {
      final match = RegExp(r'(\d+)\s*[xX]\s*(\d+)').firstMatch('${document.itemName} ${document.productType}');
      if (match != null) {
        nominalH = double.tryParse(match.group(2)!);
      }
    }

    double measuredHeight = fallbackHeight ?? nominalH ?? defaultHeight;
    double measuredFlange = defaultFlange;

    if (foldResult != null && foldResult.polygons.isNotEmpty && raw.sidewallFaceIds.isNotEmpty) {
      final candidateHeights = <double>[];
      for (final poly in foldResult.polygons) {
        if (raw.sidewallFaceIds.contains(poly.faceId)) {
          for (final v in poly.vertices) {
            // Distance perpendicular to the mouth plane
            final distNormal = ((v.x - p1.x) * normal.x +
                                (v.y - p1.y) * normal.y +
                                (v.z - p1.z) * normal.z).abs();
            if (distNormal > 5.5) continue; // Must be on or near the mouth plane

            // Distance along the width axis (must be within the mouth span)
            final t = (v.x - p1.x) * widthDirection.x +
                      (v.y - p1.y) * widthDirection.y +
                      (v.z - p1.z) * widthDirection.z;
            if (t < -5.0 || t > measuredWidth + 5.0) continue;

            // Projection along height direction
            final projH = (v.x - p1.x) * heightDirection.x +
                          (v.y - p1.y) * heightDirection.y +
                          (v.z - p1.z) * heightDirection.z;

            if (projH > 15.0) {
              candidateHeights.add(projH);
            }
          }
        }
      }

      if (candidateHeights.isNotEmpty) {
        candidateHeights.sort();
        if ((isOutsideRiser || isInsideRiser || isReducer) && nominalH != null && nominalH > 15.0) {
          measuredHeight = nominalH;
        } else if (nominalH != null && nominalH > 15.0) {
          // If nominal height is known (e.g. 100mm), choose the candidate closest to nominal height
          // that does not exceed nominal (to avoid picking up flange/coupler tabs that stick above the channel)
          final validCandidates = candidateHeights.where((h) => h <= nominalH! * 1.05).toList();
          if (validCandidates.isNotEmpty) {
            measuredHeight = validCandidates.last;
          } else {
            measuredHeight = candidateHeights.first;
          }
        } else {
          // If multiple candidate heights exist (e.g. channel rim vs flange tab),
          // the channel rim is typically the lower plateau.
          // If candidates differ by a flange tab (8-16mm), pick the rim.
          double bestH = candidateHeights.last;
          for (int i = 0; i < candidateHeights.length - 1; i++) {
            final h = candidateHeights[i];
            final diff = candidateHeights.last - h;
            if (diff >= 7.0 && diff <= 16.0 && h >= 35.0) {
              bestH = h;
              break;
            }
          }
          measuredHeight = bestH;
        }
      }
    }

    if (measuredHeight <= 15.0) {
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
    }

    // Clamp measuredHeight if derived mouth corners would protrude beyond the folded part boundary
    if (foldResult != null && foldResult.polygons.isNotEmpty) {
      double minZ = double.infinity;
      double maxZ = -double.infinity;
      for (final poly in foldResult.polygons) {
        for (final v in poly.vertices) {
          if (v.z < minZ) minZ = v.z;
          if (v.z > maxZ) maxZ = v.z;
        }
      }
      if (maxZ.isFinite && minZ.isFinite) {
        // Check +Z protrusion
        if (!isOutsideRiser && !isInsideRiser && heightDirection.z > 1e-4) {
          final currentMaxZ = math.max(
            p1.z + measuredHeight * heightDirection.z,
            p2.z + measuredHeight * heightDirection.z,
          );
          if (currentMaxZ > maxZ + 1.5) {
            final excessZ = currentMaxZ - maxZ;
            final clampedHeight = measuredHeight - excessZ / heightDirection.z;
            if (clampedHeight > 15.0) {
              measuredHeight = clampedHeight;
            }
          }
        } else if (heightDirection.z < -1e-4) {
          // Check -Z protrusion
          final currentMinZ = math.min(
            p1.z + measuredHeight * heightDirection.z,
            p2.z + measuredHeight * heightDirection.z,
          );
          if (currentMinZ < minZ - 1.5) {
            final excessZ = minZ - currentMinZ;
            final clampedHeight = measuredHeight - excessZ / (-heightDirection.z);
            if (clampedHeight > 15.0) {
              measuredHeight = clampedHeight;
            }
          }
        }
      }
    }

    // 6. Derived 4 corners of the channel mouth [P1 (floor), P3 (lip), P4 (lip), P2 (floor)]
    final p3 = CadPoint3D(
      p1.x + measuredHeight * heightDirection.x,
      p1.y + measuredHeight * heightDirection.y,
      p1.z + measuredHeight * heightDirection.z,
    );
    final p4 = CadPoint3D(
      p2.x + measuredHeight * heightDirection.x,
      p2.y + measuredHeight * heightDirection.y,
      p2.z + measuredHeight * heightDirection.z,
    );
    final derivedMouthCorners = [p1, p3, p4, p2];

    // 7. True mouth centroid (midpoint of floor & top lip)
    final center = CadPoint3D(
      (p1.x + p2.x) / 2.0 + (measuredHeight / 2.0) * heightDirection.x,
      (p1.y + p2.y) / 2.0 + (measuredHeight / 2.0) * heightDirection.y,
      (p1.z + p2.z) / 2.0 + (measuredHeight / 2.0) * heightDirection.z,
    );

    // 8. Callout anchor pinned directly on top rim mouth center
    final calloutAnchor = CadPoint3D(
      (p1.x + p2.x) / 2.0 + measuredHeight * heightDirection.x,
      (p1.y + p2.y) / 2.0 + measuredHeight * heightDirection.y,
      (p1.z + p2.z) / 2.0 + measuredHeight * heightDirection.z,
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
