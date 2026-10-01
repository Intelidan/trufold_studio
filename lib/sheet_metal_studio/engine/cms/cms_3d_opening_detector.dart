// =============================================================================
// cms_3d_opening_detector.dart
//
// Extracts raw physical candidate opening loops and boundaries from the 3D
// folded sheet-metal mesh per TRUFOLD_LEGACY_ISOLATION_CLEAN_CMS_ARCHITECTURE.md
// (Section 11).
// =============================================================================

import 'dart:math' as math;

import 'cms_scaling_controller.dart';
import '../kinematic_fold_engine.dart';
import '../../models/cad_primitives.dart';
import '../../models/cnc_punch_primitive.dart';
import '../../models/dsf_document.dart';
import '../../models/planar_sheet_face.dart';
import '../../models/fold_bend_line.dart';

/// Represents a raw, uninterpreted physical opening loop extracted from 3D topology.
class CmsRaw3DOpening {
  final String openingId;
  final List<CadPoint3D> boundary3DVertices;
  final CadPoint3D floorEdgeP1;
  final CadPoint3D floorEdgeP2;
  final CadPoint2D flatFloorEdgeP1;
  final CadPoint2D flatFloorEdgeP2;
  final String floorFaceId;
  final List<String> sidewallFaceIds;
  final CadPoint3D outwardNormal;

  const CmsRaw3DOpening({
    required this.openingId,
    required this.boundary3DVertices,
    required this.floorEdgeP1,
    required this.floorEdgeP2,
    required this.flatFloorEdgeP1,
    required this.flatFloorEdgeP2,
    required this.floorFaceId,
    required this.sidewallFaceIds,
    required this.outwardNormal,
  });
}

/// Discovers open channel mouth boundaries from the folded 3D mesh.
class Cms3DOpeningDetector {
  /// Extracts all candidate channel openings from the document and its folded 3D mesh.
  static List<CmsRaw3DOpening> detectOpenings({required DsfDocument document, required FoldedMeshResult foldResult}) {
    if (document.faces.isEmpty || foldResult.polygons.isEmpty) return const [];

    // 1. Identify all Floor Web faces (anchor base + connected riser segments)
    final floorFaces = _identifyFloorFaces(document, foldResult);
    if (floorFaces.isEmpty) return const [];

    // 2. Identify 3D standing sidewall faces connected to the floor via 90° structural bends
    final sidewallFaces = _findSidewalls(document, floorFaces, foldResult);

    // 3. For each floor face, find open terminal edges (filtering out bend lines and cheek cuts)
    final rawOpenings = <CmsRaw3DOpening>[];
    int index = 1;

    for (final floorFace in floorFaces) {
      final candidateFloorEdges = _findOpenFloorEdges(document, floorFace, sidewallFaces, foldResult);

      for (final floorEdge in candidateFloorEdges) {
        var p1Flat = floorEdge.p1;
        var p2Flat = floorEdge.p2;

        // Transform flat floor edge to 3D using floor polygon vertices
        final floor3DPoly = foldResult.polygons.firstWhere((p) => p.faceId == floorFace.id, orElse: () => foldResult.polygons.first);

        final p1_3d = _mapFlatTo3D(p1Flat, floorFace.vertices, floor3DPoly.vertices);
        final p2_3d = _mapFlatTo3D(p2Flat, floorFace.vertices, floor3DPoly.vertices);

        // Compute outward normal vector along the floor plane in true 3D
        final edgeDx = p2_3d.x - p1_3d.x;
        final edgeDy = p2_3d.y - p1_3d.y;
        final edgeDz = p2_3d.z - p1_3d.z;
        final edgeLen = math.sqrt(edgeDx * edgeDx + edgeDy * edgeDy + edgeDz * edgeDz);
        if (edgeLen < 1e-4) continue;

        final uW = CadPoint3D(edgeDx / edgeLen, edgeDy / edgeLen, edgeDz / edgeLen);
        final floorNorm = floor3DPoly.normal;

        // In-plane perpendicular: uW x floorNorm
        var normX = uW.y * floorNorm.z - uW.z * floorNorm.y;
        var normY = uW.z * floorNorm.x - uW.x * floorNorm.z;
        var normZ = uW.x * floorNorm.y - uW.y * floorNorm.x;
        final normLen = math.sqrt(normX * normX + normY * normY + normZ * normZ);
        if (normLen > 1e-4) {
          normX /= normLen;
          normY /= normLen;
          normZ /= normLen;
        }

        // Ensure outward normal points AWAY from floor center
        final mid3D = CadPoint3D((p1_3d.x + p2_3d.x) / 2.0, (p1_3d.y + p2_3d.y) / 2.0, (p1_3d.z + p2_3d.z) / 2.0);
        final floorCenter = _polygonCenter3D(floor3DPoly.vertices);
        final toMidX = mid3D.x - floorCenter.x;
        final toMidY = mid3D.y - floorCenter.y;
        final toMidZ = mid3D.z - floorCenter.z;
        if (normX * toMidX + normY * toMidY + normZ * toMidZ < 0) {
          normX = -normX;
          normY = -normY;
          normZ = -normZ;
        }
        final outwardNormal = CadPoint3D(normX, normY, normZ);

        // Find sidewall faces adjacent to p1 and p2
        final adjacentSidewallIds = <String>[];
        for (final sw in sidewallFaces) {
          adjacentSidewallIds.add(sw.id);
        }

        CadPoint3D finalP1_3d = p1_3d;
        CadPoint3D finalP2_3d = p2_3d;
        CadPoint3D finalNormal = outwardNormal;

        // SS1: Outside Riser angled mouth and bending architecture support
        final docType = '${document.productType} ${document.itemName}'.toLowerCase();
        final isReducer = docType.contains('reducer') || CmsScalingController.isReducerGeometry(document);
        final isOutsideRiser = !isReducer && docType.contains('outside') && (docType.contains('riser') || docType.contains('rise'));
        final isInsideRiser = !isReducer && ((docType.contains('inside') && (docType.contains('riser') || docType.contains('rise'))) ||
            CmsScalingController.isInsideRiserGeometry(document));
        final isTee = docType.contains('tee');
        final isCross = docType.contains('cross');

        if (isOutsideRiser) {
          final cheekBends = document.bends
              .where((b) => (b.targetAngleDeg.abs() - 90.0).abs() < 15.0 && b.role != BendLineRole.flange && !b.id.toUpperCase().startsWith('FL'))
              .toList();
          final isHorizontal = cheekBends.isNotEmpty &&
              (cheekBends.first.p2.x - cheekBends.first.p1.x).abs() > (cheekBends.first.p2.y - cheekBends.first.p1.y).abs();

          final nominalH = (document.parameters['height'] as num?)?.toDouble() ?? 100.0;
          final halfH = nominalH / 2.0;

          if (isHorizontal) {
            // 90° Outside Riser: mouths pass directly through coupler holes on cheeks
            final isPort1 = (p1_3d.x + p2_3d.x) / 2.0 < floorCenter.x;

            cheekBends.sort((a, b) => ((a.p1.y + a.p2.y) / 2.0).compareTo((b.p1.y + b.p2.y) / 2.0));
            final b1Y = (cheekBends.first.p1.y + cheekBends.first.p2.y) / 2.0;
            final b2Y = (cheekBends.last.p1.y + cheekBends.last.p2.y) / 2.0;
            final yMid = (b1Y + b2Y) / 2.0;

            final portPunches = document.punches.where((p) {
              final isMatchingSide = isPort1 ? (p.center.x < floorCenter.x) : (p.center.x > floorCenter.x);
              return isMatchingSide && (p.isSlot || p.type == PunchType.obroundSlot || p.role == CncPunchRole.coupler);
            }).toList();

            final cheek1Punches = portPunches.where((p) => p.center.y < yMid).toList();
            final cheek2Punches = portPunches.where((p) => p.center.y > yMid).toList();

            CadPoint3D? m1_3d;
            CadPoint3D? m2_3d;

            if (cheek1Punches.isNotEmpty) {
              double sx = 0, sy = 0, sz = 0;
              for (final p in cheek1Punches) {
                final pt3d = foldResult.punchCenters3D[p.id] ?? _mapFlatTo3D(p.center, floorFace.vertices, floor3DPoly.vertices);
                sx += pt3d.x; sy += pt3d.y; sz += pt3d.z;
              }
              m1_3d = CadPoint3D(sx / cheek1Punches.length, sy / cheek1Punches.length, sz / cheek1Punches.length);
            }

            if (cheek2Punches.isNotEmpty) {
              double sx = 0, sy = 0, sz = 0;
              for (final p in cheek2Punches) {
                final pt3d = foldResult.punchCenters3D[p.id] ?? _mapFlatTo3D(p.center, floorFace.vertices, floor3DPoly.vertices);
                sx += pt3d.x; sy += pt3d.y; sz += pt3d.z;
              }
              m2_3d = CadPoint3D(sx / cheek2Punches.length, sy / cheek2Punches.length, sz / cheek2Punches.length);
            }

            if (m1_3d != null && m2_3d != null) {
              final vHx = isPort1 ? -1.0 / math.sqrt(2) : 1.0 / math.sqrt(2);
              final vHz = 1.0 / math.sqrt(2);

              final normX = isPort1 ? -1.0 / math.sqrt(2) : 1.0 / math.sqrt(2);
              const normY = 0.0;
              final normZ = -1.0 / math.sqrt(2);
              finalNormal = CadPoint3D(normX, normY, normZ);

              finalP1_3d = CadPoint3D(
                m1_3d.x - halfH * vHx,
                m1_3d.y,
                m1_3d.z - halfH * vHz,
              );
              finalP2_3d = CadPoint3D(
                m2_3d.x - halfH * vHx,
                m2_3d.y,
                m2_3d.z - halfH * vHz,
              );

              final c1FlatX = cheek1Punches.map((p) => p.center.x).reduce((a, b) => a + b) / cheek1Punches.length;
              final c1FlatY = cheek1Punches.map((p) => p.center.y).reduce((a, b) => a + b) / cheek1Punches.length;
              final c2FlatX = cheek2Punches.map((p) => p.center.x).reduce((a, b) => a + b) / cheek2Punches.length;
              final c2FlatY = cheek2Punches.map((p) => p.center.y).reduce((a, b) => a + b) / cheek2Punches.length;
              p1Flat = CadPoint2D(c1FlatX, c1FlatY);
              p2Flat = CadPoint2D(c2FlatX, c2FlatY);
            }
          } else {
            // 45° Outside Riser: cheek bends run along Y.
            cheekBends.sort((a, b) => ((a.p1.x + a.p2.x) / 2.0).compareTo((b.p1.x + b.p2.x) / 2.0));
            final b1X = (cheekBends.first.p1.x + cheekBends.first.p2.x) / 2.0;
            final b2X = (cheekBends.last.p1.x + cheekBends.last.p2.x) / 2.0;
            final xMid = (b1X + b2X) / 2.0;

            final isStraightPort = (p1_3d.y + p2_3d.y) / 2.0 < floorCenter.y;
            final portPunches = document.punches.where((p) {
              final isMatchingSide = isStraightPort ? (p.center.y < 60.0) : (p.center.y > 60.0);
              return isMatchingSide && (p.isSlot || p.type == PunchType.obroundSlot || p.role == CncPunchRole.coupler);
            }).toList();

            final cheek1Punches = portPunches.where((p) => p.center.x < xMid).toList();
            final cheek2Punches = portPunches.where((p) => p.center.x > xMid).toList();

            CadPoint3D? m1_3d;
            CadPoint3D? m2_3d;

            if (cheek1Punches.isNotEmpty) {
              double sx = 0, sy = 0, sz = 0;
              for (final p in cheek1Punches) {
                final pt3d = foldResult.punchCenters3D[p.id] ?? _mapFlatTo3D(p.center, floorFace.vertices, floor3DPoly.vertices);
                sx += pt3d.x; sy += pt3d.y; sz += pt3d.z;
              }
              m1_3d = CadPoint3D(sx / cheek1Punches.length, sy / cheek1Punches.length, sz / cheek1Punches.length);
            }

            if (cheek2Punches.isNotEmpty) {
              double sx = 0, sy = 0, sz = 0;
              for (final p in cheek2Punches) {
                final pt3d = foldResult.punchCenters3D[p.id] ?? _mapFlatTo3D(p.center, floorFace.vertices, floor3DPoly.vertices);
                sx += pt3d.x; sy += pt3d.y; sz += pt3d.z;
              }
              m2_3d = CadPoint3D(sx / cheek2Punches.length, sy / cheek2Punches.length, sz / cheek2Punches.length);
            }

            if (m1_3d != null && m2_3d != null) {
              if (isStraightPort) {
                finalNormal = const CadPoint3D(0.0, -1.0, 0.0);
                finalP1_3d = CadPoint3D(m1_3d.x, m1_3d.y, m1_3d.z - halfH);
                finalP2_3d = CadPoint3D(m2_3d.x, m2_3d.y, m2_3d.z - halfH);
              } else {
                finalNormal = const CadPoint3D(0.0, 0.7071067811865475, -0.7071067811865475);
                const vHy = 0.7071067811865475;
                const vHz = 0.7071067811865475;
                finalP1_3d = CadPoint3D(m1_3d.x, m1_3d.y - halfH * vHy, m1_3d.z - halfH * vHz);
                finalP2_3d = CadPoint3D(m2_3d.x, m2_3d.y - halfH * vHy, m2_3d.z - halfH * vHz);
              }

              final c1FlatX = cheek1Punches.map((p) => p.center.x).reduce((a, b) => a + b) / cheek1Punches.length;
              final c1FlatY = cheek1Punches.map((p) => p.center.y).reduce((a, b) => a + b) / cheek1Punches.length;
              final c2FlatX = cheek2Punches.map((p) => p.center.x).reduce((a, b) => a + b) / cheek2Punches.length;
              final c2FlatY = cheek2Punches.map((p) => p.center.y).reduce((a, b) => a + b) / cheek2Punches.length;
              p1Flat = CadPoint2D(c1FlatX, c1FlatY);
              p2Flat = CadPoint2D(c2FlatX, c2FlatY);
            }
          }
        } else if (isInsideRiser) {
          final cheekBends = document.bends
              .where((b) => (b.targetAngleDeg.abs() - 90.0).abs() < 15.0 && b.role != BendLineRole.flange && !b.id.toUpperCase().startsWith('FL'))
              .toList()
            ..sort((a, b) => ((a.p1.x + a.p2.x) / 2.0).compareTo((b.p1.x + b.p2.x) / 2.0));

          final xMid = cheekBends.isNotEmpty ? (cheekBends.first.p1.x + cheekBends.last.p1.x) / 2.0 : floorCenter.x;

          final bends45 = document.bends.where((b) => (b.targetAngleDeg.abs() - 45.0).abs() < 15.0).toList()
            ..sort((a, b) => ((a.p1.y + a.p2.y) / 2.0).compareTo((b.p1.y + b.p2.y) / 2.0));
          final is90InsideRiser = bends45.length >= 2;

          final yMid = is90InsideRiser
              ? (bends45.first.p1.y + bends45.last.p1.y) / 2.0
              : (bends45.isNotEmpty ? bends45.first.p1.y - 15.0 : floorCenter.y);

          final nominalH = (document.parameters['height'] as num?)?.toDouble() ?? 100.0;
          final halfH = nominalH / 2.0;

          final isPort1 = (p1Flat.y + p2Flat.y) / 2.0 > yMid;

          final portPunches = document.punches.where((p) {
            final isMatchingSide = isPort1 ? (p.center.y > yMid) : (p.center.y < yMid);
            return isMatchingSide && (p.isSlot || p.type == PunchType.obroundSlot || p.role == CncPunchRole.coupler);
          }).toList();

          final cheek1Punches = portPunches.where((p) => p.center.x < xMid).toList();
          final cheek2Punches = portPunches.where((p) => p.center.x > xMid).toList();

          CadPoint3D? m1_3d;
          CadPoint3D? m2_3d;

          if (cheek1Punches.isNotEmpty) {
            double sx = 0, sy = 0, sz = 0;
            for (final p in cheek1Punches) {
              final pt3d = foldResult.punchCenters3D[p.id] ?? _mapFlatTo3D(p.center, floorFace.vertices, floor3DPoly.vertices);
              sx += pt3d.x; sy += pt3d.y; sz += pt3d.z;
            }
            m1_3d = CadPoint3D(sx / cheek1Punches.length, sy / cheek1Punches.length, sz / cheek1Punches.length);
          }

          if (cheek2Punches.isNotEmpty) {
            double sx = 0, sy = 0, sz = 0;
            for (final p in cheek2Punches) {
              final pt3d = foldResult.punchCenters3D[p.id] ?? _mapFlatTo3D(p.center, floorFace.vertices, floor3DPoly.vertices);
              sx += pt3d.x; sy += pt3d.y; sz += pt3d.z;
            }
            m2_3d = CadPoint3D(sx / cheek2Punches.length, sy / cheek2Punches.length, sz / cheek2Punches.length);
          }

          if (m1_3d != null && m2_3d != null) {
            if (isPort1) {
              // Port 1 (Top Port): floor flap tilted 45° UP along +Y
              finalNormal = const CadPoint3D(0.0, 0.7071067811865475, 0.7071067811865475);
              const vHy = -0.7071067811865475;
              const vHz = 0.7071067811865475;
              finalP1_3d = CadPoint3D(m1_3d.x, m1_3d.y - halfH * vHy, m1_3d.z - halfH * vHz);
              finalP2_3d = CadPoint3D(m2_3d.x, m2_3d.y - halfH * vHy, m2_3d.z - halfH * vHz);
            } else {
              // Port 2 (Bottom Port):
              if (is90InsideRiser) {
                // 90° Inside Riser: floor flap tilted 45° UP along -Y
                finalNormal = const CadPoint3D(0.0, -0.7071067811865475, 0.7071067811865475);
                const vHy = 0.7071067811865475;
                const vHz = 0.7071067811865475;
                finalP1_3d = CadPoint3D(m1_3d.x, m1_3d.y - halfH * vHy, m1_3d.z - halfH * vHz);
                finalP2_3d = CadPoint3D(m2_3d.x, m2_3d.y - halfH * vHy, m2_3d.z - halfH * vHz);
              } else {
                // 45° Inside Riser: bottom port is straight (horizontal floor)
                finalNormal = const CadPoint3D(0.0, -1.0, 0.0);
                finalP1_3d = CadPoint3D(m1_3d.x, p1_3d.y, p1_3d.z);
                finalP2_3d = CadPoint3D(m2_3d.x, p2_3d.y, p2_3d.z);
              }
            }

            final c1FlatX = cheek1Punches.map((p) => p.center.x).reduce((a, b) => a + b) / cheek1Punches.length;
            final c1FlatY = cheek1Punches.map((p) => p.center.y).reduce((a, b) => a + b) / cheek1Punches.length;
            final c2FlatX = cheek2Punches.map((p) => p.center.x).reduce((a, b) => a + b) / cheek2Punches.length;
            final c2FlatY = cheek2Punches.map((p) => p.center.y).reduce((a, b) => a + b) / cheek2Punches.length;
            p1Flat = CadPoint2D(c1FlatX, c1FlatY);
            p2Flat = CadPoint2D(c2FlatX, c2FlatY);
          }
        } else if (isReducer) {
          final cheekBends = document.bends
              .where((b) => (b.targetAngleDeg.abs() - 90.0).abs() < 15.0 && b.role != BendLineRole.flange && !b.id.toUpperCase().startsWith('FL'))
              .toList()
            ..sort((a, b) => ((a.p1.x + a.p2.x) / 2.0).compareTo((b.p1.x + b.p2.x) / 2.0));

          final xMid = cheekBends.isNotEmpty ? (cheekBends.first.p1.x + cheekBends.last.p1.x) / 2.0 : floorCenter.x;
          final yMid = (floorFace.vertices.map((v) => v.y).reduce(math.min) + floorFace.vertices.map((v) => v.y).reduce(math.max)) / 2.0;

          final isPort1 = (p1Flat.y + p2Flat.y) / 2.0 < yMid;
          double? nominalH = isPort1
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
          final halfH = nominalH / 2.0;

          final portPunches = document.punches.where((p) {
            final isMatchingSide = isPort1 ? (p.center.y < yMid) : (p.center.y > yMid);
            return isMatchingSide && (p.isSlot || p.type == PunchType.obroundSlot || p.role == CncPunchRole.coupler);
          }).toList();

          final cheek1Punches = portPunches.where((p) => p.center.x < xMid).toList();
          final cheek2Punches = portPunches.where((p) => p.center.x > xMid).toList();

          CadPoint3D? m1_3d;
          CadPoint3D? m2_3d;

          if (cheek1Punches.isNotEmpty) {
            double sx = 0, sy = 0, sz = 0;
            for (final p in cheek1Punches) {
              final pt3d = foldResult.punchCenters3D[p.id] ?? _mapFlatTo3D(p.center, floorFace.vertices, floor3DPoly.vertices);
              sx += pt3d.x; sy += pt3d.y; sz += pt3d.z;
            }
            m1_3d = CadPoint3D(sx / cheek1Punches.length, sy / cheek1Punches.length, sz / cheek1Punches.length);
          }

          if (cheek2Punches.isNotEmpty) {
            double sx = 0, sy = 0, sz = 0;
            for (final p in cheek2Punches) {
              final pt3d = foldResult.punchCenters3D[p.id] ?? _mapFlatTo3D(p.center, floorFace.vertices, floor3DPoly.vertices);
              sx += pt3d.x; sy += pt3d.y; sz += pt3d.z;
            }
            m2_3d = CadPoint3D(sx / cheek2Punches.length, sy / cheek2Punches.length, sz / cheek2Punches.length);
          }

          if (m1_3d != null && m2_3d != null) {
            finalNormal = isPort1 ? const CadPoint3D(0.0, -1.0, 0.0) : const CadPoint3D(0.0, 1.0, 0.0);
            finalP1_3d = CadPoint3D(m1_3d.x, m1_3d.y, m1_3d.z - halfH);
            finalP2_3d = CadPoint3D(m2_3d.x, m2_3d.y, m2_3d.z - halfH);

            final c1FlatX = cheek1Punches.map((p) => p.center.x).reduce((a, b) => a + b) / cheek1Punches.length;
            final c1FlatY = cheek1Punches.map((p) => p.center.y).reduce((a, b) => a + b) / cheek1Punches.length;
            final c2FlatX = cheek2Punches.map((p) => p.center.x).reduce((a, b) => a + b) / cheek2Punches.length;
            final c2FlatY = cheek2Punches.map((p) => p.center.y).reduce((a, b) => a + b) / cheek2Punches.length;
            p1Flat = CadPoint2D(c1FlatX, c1FlatY);
            p2Flat = CadPoint2D(c2FlatX, c2FlatY);
          }
        } else if ((isTee || isCross) && docType.contains('trunking')) {
          // For Trunking Tee and Cross fittings, the physical channel mouth is strictly the planar floor edge
          // (terminal boundary of the channel bed), spanning perpendicularly between sidewalls.
          // Never deflect the port angle using cheek punches from non-collinear walls.
        } else {
          // General / Bend / Tray accessory opening:
          // If there are explicit coupler holes marked on the sidewalls of this opening,
          // the opening mouth plane and border MUST pass directly through the center
          // of the coupler holes, provided the cheek vector is aligned with the opening!
          final couplerPunches = document.punches.where((p) => p.role == CncPunchRole.coupler).toList();
          if (couplerPunches.isNotEmpty) {
            final portCouplers = couplerPunches.where((p) {
              final pt3d = foldResult.punchCenters3D[p.id] ?? _mapFlatTo3D(p.center, floorFace.vertices, floor3DPoly.vertices);
              final distAlongNormal = (mid3D.x - pt3d.x) * finalNormal.x +
                                      (mid3D.y - pt3d.y) * finalNormal.y +
                                      (mid3D.z - pt3d.z) * finalNormal.z;
              if (distAlongNormal < -15.0 || distAlongNormal > 80.0) return false;
              final distAcross = ((pt3d.x - mid3D.x) * uW.x + (pt3d.y - mid3D.y) * uW.y + (pt3d.z - mid3D.z) * uW.z).abs();
              return distAcross <= edgeLen / 2.0 + 35.0;
            }).toList();

            final cheek1Punches = portCouplers.where((p) {
              final pt3d = foldResult.punchCenters3D[p.id] ?? _mapFlatTo3D(p.center, floorFace.vertices, floor3DPoly.vertices);
              return pt3d.distanceTo(p1_3d) < pt3d.distanceTo(p2_3d);
            }).toList();

            final cheek2Punches = portCouplers.where((p) {
              final pt3d = foldResult.punchCenters3D[p.id] ?? _mapFlatTo3D(p.center, floorFace.vertices, floor3DPoly.vertices);
              return pt3d.distanceTo(p2_3d) <= pt3d.distanceTo(p1_3d);
            }).toList();

            if (cheek1Punches.isNotEmpty && cheek2Punches.isNotEmpty) {
              // Item 5: The port aperture/border must pass strictly through the column of coupler holes
              // AT THE END EDGE (the outermost column closest to the port opening mouth plane).
              final cheek1WithDist = cheek1Punches.map((p) {
                final pt3d = foldResult.punchCenters3D[p.id] ?? _mapFlatTo3D(p.center, floorFace.vertices, floor3DPoly.vertices);
                return (punch: p, pt3d: pt3d, dist: pt3d.distanceTo(p1_3d));
              }).toList();
              final minD1 = cheek1WithDist.map((e) => e.dist).reduce(math.min);
              final endEdgeCheek1 = cheek1WithDist.where((e) => e.dist <= minD1 + 12.0).toList();

              final cheek2WithDist = cheek2Punches.map((p) {
                final pt3d = foldResult.punchCenters3D[p.id] ?? _mapFlatTo3D(p.center, floorFace.vertices, floor3DPoly.vertices);
                return (punch: p, pt3d: pt3d, dist: pt3d.distanceTo(p2_3d));
              }).toList();
              final minD2 = cheek2WithDist.map((e) => e.dist).reduce(math.min);
              final endEdgeCheek2 = cheek2WithDist.where((e) => e.dist <= minD2 + 12.0).toList();

              double s1x = 0, s1y = 0, s1z = 0;
              for (final e in endEdgeCheek1) {
                s1x += e.pt3d.x; s1y += e.pt3d.y; s1z += e.pt3d.z;
              }
              final m1_3d = CadPoint3D(s1x / endEdgeCheek1.length, s1y / endEdgeCheek1.length, s1z / endEdgeCheek1.length);

              double s2x = 0, s2y = 0, s2z = 0;
              for (final e in endEdgeCheek2) {
                s2x += e.pt3d.x; s2y += e.pt3d.y; s2z += e.pt3d.z;
              }
              final m2_3d = CadPoint3D(s2x / endEdgeCheek2.length, s2y / endEdgeCheek2.length, s2z / endEdgeCheek2.length);

              final cheekDx = m2_3d.x - m1_3d.x;
              final cheekDy = m2_3d.y - m1_3d.y;
              final cheekDz = m2_3d.z - m1_3d.z;
              final cheekLen = math.sqrt(cheekDx * cheekDx + cheekDy * cheekDy + cheekDz * cheekDz);
              final isAligned = cheekLen > 1e-3 &&
                  ((cheekDx / cheekLen) * uW.x + (cheekDy / cheekLen) * uW.y + (cheekDz / cheekLen) * uW.z).abs() > 0.985;

              if (isAligned) {
                final avgPt = CadPoint3D((m1_3d.x + m2_3d.x) / 2.0, (m1_3d.y + m2_3d.y) / 2.0, (m1_3d.z + m2_3d.z) / 2.0);
                final distAlongNormal = (mid3D.x - avgPt.x) * finalNormal.x +
                                        (mid3D.y - avgPt.y) * finalNormal.y +
                                        (mid3D.z - avgPt.z) * finalNormal.z;

                final shiftX = -distAlongNormal * finalNormal.x;
                final shiftY = -distAlongNormal * finalNormal.y;
                final shiftZ = -distAlongNormal * finalNormal.z;

                finalP1_3d = CadPoint3D(p1_3d.x + shiftX, p1_3d.y + shiftY, p1_3d.z + shiftZ);
                finalP2_3d = CadPoint3D(p2_3d.x + shiftX, p2_3d.y + shiftY, p2_3d.z + shiftZ);

                p1Flat = CadPoint2D(p1Flat.x + shiftX, p1Flat.y + shiftY);
                p2Flat = CadPoint2D(p2Flat.x + shiftX, p2Flat.y + shiftY);
              }
            }
          }
        }

        // Collect loop vertices (Floor edge P1 -> P2)
        final loop3D = <CadPoint3D>[finalP1_3d, finalP2_3d];

        rawOpenings.add(
          CmsRaw3DOpening(
            openingId: 'raw_opening_$index',
            boundary3DVertices: loop3D,
            floorEdgeP1: finalP1_3d,
            floorEdgeP2: finalP2_3d,
            flatFloorEdgeP1: p1Flat,
            flatFloorEdgeP2: p2Flat,
            floorFaceId: floorFace.id,
            sidewallFaceIds: adjacentSidewallIds,
            outwardNormal: finalNormal,
          ),
        );
        index++;
      }
    }

    return rawOpenings;
  }

  static List<PlanarSheetFace> _identifyFloorFaces(DsfDocument doc, FoldedMeshResult mesh) {
    if (doc.faces.isEmpty) return const [];

    // 1. Rank candidate faces by structural connectivity (attached to 90° structural sidewall bends) + area
    PlanarSheetFace? baseFace;
    double bestScore = -1.0;

    for (final face in doc.faces) {
      int structuralBends = 0;
      for (final b in doc.bends) {
        if (b.role != BendLineRole.flange && (b.parentFaceId == face.id || b.childFaceId == face.id) && (b.targetAngleDeg.abs() - 90.0).abs() < 15.0) {
          structuralBends++;
        }
      }

      // Check folded 3D normal horizontality (|normal.z| > 0.7)
      final polyMatches = mesh.polygons.where((p) => p.faceId == face.id);
      final isHorizontal = polyMatches.isNotEmpty && polyMatches.first.normal.z.abs() > 0.7;

      if (mesh.polygons.isNotEmpty && !isHorizontal) {
        continue;
      }

      double score = structuralBends * 10000.0 + face.areaMm2;
      if (face.isBaseAnchor || face.id == doc.baseFaceId) {
        score += 50000.0;
      }

      if (score > bestScore) {
        bestScore = score;
        baseFace = face;
      }
    }

    baseFace ??= doc.faces.first;

    // 2. Identify initial sidewalls attached to baseFace via 90° bends
    final sidewallIds = <String>{};
    for (final b in doc.bends) {
      if ((b.parentFaceId == baseFace.id || b.childFaceId == baseFace.id) && b.role != BendLineRole.flange && (b.targetAngleDeg.abs() - 90.0).abs() < 15.0) {
        final otherId = b.parentFaceId == baseFace.id ? b.childFaceId : b.parentFaceId;
        sidewallIds.add(otherId);
      }
    }

    // 3. Traverse connected floor faces (e.g. angled riser segments or stepped transitions)
    final floorFaceMap = <String, PlanarSheetFace>{baseFace.id: baseFace};
    final queue = <PlanarSheetFace>[baseFace];

    while (queue.isNotEmpty) {
      final curr = queue.removeAt(0);
      for (final b in doc.bends) {
        final connects = b.parentFaceId == curr.id || b.childFaceId == curr.id;
        if (!connects || b.role == BendLineRole.flange) continue;

        final otherId = b.parentFaceId == curr.id ? b.childFaceId : b.parentFaceId;
        if (floorFaceMap.containsKey(otherId) || sidewallIds.contains(otherId)) continue;

        final otherFace = doc.faces.firstWhere(
          (f) => f.id == otherId,
          orElse: () => PlanarSheetFace(id: otherId, vertices: const []),
        );
        if (otherFace.vertices.isEmpty) continue;

        // Ensure this face is not a sidewall or flange
        // Sidewalls have 90° bends to base and stand vertical (|normal.z| < 0.3)
        final polyMatches = mesh.polygons.where((p) => p.faceId == otherId);
        final isVerticalWall = polyMatches.isNotEmpty && polyMatches.first.normal.z.abs() < 0.3;
        if (!isVerticalWall) {
          floorFaceMap[otherId] = otherFace;
          queue.add(otherFace);
        }
      }
    }

    return floorFaceMap.values.toList();
  }

  static List<PlanarSheetFace> _findSidewalls(DsfDocument doc, List<PlanarSheetFace> floorFaces, FoldedMeshResult mesh) {
    final sidewalls = <PlanarSheetFace>[];
    final floorFaceIds = floorFaces.map((f) => f.id).toSet();

    // 1. Initial sidewalls directly attached to floor via 90° structural bends
    final queue = <String>[];
    for (final bend in doc.bends) {
      final parentIsFloor = floorFaceIds.contains(bend.parentFaceId);
      final childIsFloor = floorFaceIds.contains(bend.childFaceId);
      if (!parentIsFloor && !childIsFloor) continue;
      if (bend.role == BendLineRole.flange) continue;

      final otherFaceId = parentIsFloor ? bend.childFaceId : bend.parentFaceId;
      if (floorFaceIds.contains(otherFaceId)) continue;

      final otherFace = doc.faces.firstWhere(
        (f) => f.id == otherFaceId,
        orElse: () => PlanarSheetFace(id: otherFaceId, vertices: const []),
      );

      if (otherFace.vertices.isNotEmpty && (bend.targetAngleDeg.abs() - 90.0).abs() < 15.0) {
        if (!sidewalls.any((s) => s.id == otherFace.id)) {
          sidewalls.add(otherFace);
          queue.add(otherFace.id);
        }
      }
    }

    // 2. Multi-faceted sidewalls connected via angle bends (e.g. 45° bend cheek facets in 90° bend)
    while (queue.isNotEmpty) {
      final currentId = queue.removeAt(0);
      for (final bend in doc.bends) {
        if (bend.role == BendLineRole.flange) continue;
        final connects = bend.parentFaceId == currentId || bend.childFaceId == currentId;
        if (!connects) continue;

        final neighborId = bend.parentFaceId == currentId ? bend.childFaceId : bend.parentFaceId;
        if (floorFaceIds.contains(neighborId) || sidewalls.any((s) => s.id == neighborId)) continue;

        final neighborFace = doc.faces.firstWhere(
          (f) => f.id == neighborId,
          orElse: () => PlanarSheetFace(id: neighborId, vertices: const []),
        );
        if (neighborFace.vertices.isEmpty) continue;

        // If neighbor is tagged as sideWall or stands vertical in 3D, add it to sidewalls!
        final polyMatches = mesh.polygons.where((p) => p.faceId == neighborId);
        final isVertical = polyMatches.isNotEmpty && polyMatches.first.normal.z.abs() < 0.2;
        if (neighborFace.role == FaceRole.sideWall || isVertical) {
          sidewalls.add(neighborFace);
          queue.add(neighborId);
        }
      }
    }

    return sidewalls;
  }

  static bool _isEdgeAlongSidewall(CadPoint3D p1, CadPoint3D p2, List<PlanarSheetFace> sidewalls, FoldedMeshResult foldResult) {
    for (final sw in sidewalls) {
      final swPolys = foldResult.polygons.where((p) => p.faceId == sw.id);
      if (swPolys.isEmpty) continue;
      final swPoly = swPolys.first;
      if (swPoly.vertices.isEmpty) continue;

      // Check distance of p1 and p2 to sidewall plane
      final v0 = swPoly.vertices.first;
      final norm = swPoly.normal;
      final d1 = ((p1.x - v0.x) * norm.x + (p1.y - v0.y) * norm.y + (p1.z - v0.z) * norm.z).abs();
      final d2 = ((p2.x - v0.x) * norm.x + (p2.y - v0.y) * norm.y + (p2.z - v0.z) * norm.z).abs();

      if (d1 < 5.0 && d2 < 5.0) {
        // Both endpoints lie in the plane of this single sidewall (cheek cut/seam)
        return true;
      }
    }
    return false;
  }

  static List<({CadPoint2D p1, CadPoint2D p2})> _findOpenFloorEdges(
    DsfDocument doc,
    PlanarSheetFace floor,
    List<PlanarSheetFace> sidewalls,
    FoldedMeshResult mesh,
  ) {
    final openEdges = <({CadPoint2D p1, CadPoint2D p2})>[];
    final verts = floor.vertices;
    if (verts.length < 3) return openEdges;

    final floor3DPoly = mesh.polygons.firstWhere((p) => p.faceId == floor.id, orElse: () => mesh.polygons.first);

    final n = verts.length;
    for (int i = 0; i < n; i++) {
      final p1 = verts[i];
      final p2 = verts[(i + 1) % n];
      final edgeLen = p1.distanceTo(p2);
      if (edgeLen < 15.0) continue; // Skip tiny relief notches

      // Check if any bend line lies on or very close to this edge
      bool hasBend = false;
      for (final b in doc.bends) {
        if (_segmentMatchesBend(p1, p2, b)) {
          hasBend = true;
          break;
        }
      }
      if (hasBend) continue;

      // Check if edge is a cheek cut running along a single sidewall
      final p1_3d = _mapFlatTo3D(p1, floor.vertices, floor3DPoly.vertices);
      final p2_3d = _mapFlatTo3D(p2, floor.vertices, floor3DPoly.vertices);

      if (_isEdgeAlongSidewall(p1_3d, p2_3d, sidewalls, mesh)) {
        continue; // Cheek cut along sidewall seam, not a channel mouth
      }

      openEdges.add((p1: p1, p2: p2));
    }
    return openEdges;
  }

  static bool _segmentMatchesBend(CadPoint2D p1, CadPoint2D p2, FoldBendLine bend) {
    final bp1 = bend.p1;
    final bp2 = bend.p2;

    // Check distance of endpoints to bend line (tolerant of corner relief notches)
    final d1 = _distPointToSeg(p1, bp1, bp2);
    final d2 = _distPointToSeg(p2, bp1, bp2);
    if (d1 < 5.0 && d2 < 5.0) return true;

    final bd1 = _distPointToSeg(bp1, p1, p2);
    final bd2 = _distPointToSeg(bp2, p1, p2);
    if (bd1 < 5.0 && bd2 < 5.0) return true;

    return false;
  }

  static double _distPointToSeg(CadPoint2D p, CadPoint2D a, CadPoint2D b) {
    final l2 = (b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y);
    if (l2 < 1e-6) return p.distanceTo(a);
    final t = math.max(0.0, math.min(1.0, ((p.x - a.x) * (b.x - a.x) + (p.y - a.y) * (b.y - a.y)) / l2));
    final proj = CadPoint2D(a.x + t * (b.x - a.x), a.y + t * (b.y - a.y));
    return p.distanceTo(proj);
  }

  static CadPoint3D _mapFlatTo3D(CadPoint2D pt, List<CadPoint2D> flatPoly, List<CadPoint3D> poly3D) {
    if (flatPoly.isEmpty || poly3D.isEmpty) return CadPoint3D(pt.x, pt.y, 0);

    // Find closest vertex in flatPoly
    int bestIdx = 0;
    double minDist = double.infinity;
    for (int i = 0; i < flatPoly.length; i++) {
      final d = pt.distanceTo(flatPoly[i]);
      if (d < minDist) {
        minDist = d;
        bestIdx = i;
      }
    }

    if (minDist < 2.0 && bestIdx < poly3D.length) {
      return poly3D[bestIdx];
    }
    return CadPoint3D(pt.x, pt.y, 0.0);
  }

  static CadPoint3D _polygonCenter3D(List<CadPoint3D> vertices) {
    if (vertices.isEmpty) return const CadPoint3D(0, 0, 0);
    double sx = 0, sy = 0, sz = 0;
    for (final v in vertices) {
      sx += v.x;
      sy += v.y;
      sz += v.z;
    }
    final inv = 1.0 / vertices.length;
    return CadPoint3D(sx * inv, sy * inv, sz * inv);
  }
}
