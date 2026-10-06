// =============================================================================
// kinematic_fold_engine.dart
//
// Pure Dart Forward-Kinematic Sheet Metal Folding Engine.
// Builds the Directed Acyclic Graph (DAG) of planar sheet metal panels and
// calculates exact 3D spatial coordinates using arbitrary-axis Rodrigues rotations.
//
// Supports progressive folding factor t in [0.0, 1.0] for live UI animations:
// - t = 0.0: Completely flat sheet metal blank (all Z = 0.0)
// - t = 1.0: Fully formed 3D sheet metal product
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/cad_primitives.dart';
import '../models/fold_bend_line.dart';
import '../models/planar_sheet_face.dart';
import '../models/cnc_punch_primitive.dart';
import '../models/dsf_document.dart';
import 'matrix4_math_helper.dart';

/// Result of folding calculation containing all 3D polygons and metadata
class FoldedMeshResult {
  final List<CadFoldedPolygon3D> polygons;
  final List<CadFoldedPolygon3D> filletPolygons;
  final List<CadFoldedPolygon3D> thicknessPolygons;
  final double boundWidth;
  final double boundLength;
  final double boundHeight;
  final CadPoint3D center;
  final Map<String, CadPoint3D> punchCenters3D;

  const FoldedMeshResult({
    required this.polygons,
    this.filletPolygons = const [],
    this.thicknessPolygons = const [],
    required this.boundWidth,
    required this.boundLength,
    required this.boundHeight,
    required this.center,
    this.punchCenters3D = const {},
  });

  /// All polygons including planar faces, curved bend arc fillets, and physical thickness rims
  List<CadFoldedPolygon3D> get allPolygons => [...polygons, ...filletPolygons, ...thicknessPolygons];

  /// Translates all vertices in this mesh by [dx], [dy], [dz], with optional [colorOverride] and [faceIdPrefix].
  FoldedMeshResult translate(double dx, double dy, double dz, {Color? colorOverride, String? faceIdPrefix}) {
    CadPoint3D transPt(CadPoint3D p) => CadPoint3D(p.x + dx, p.y + dy, p.z + dz);
    CadFoldedPolygon3D transPoly(CadFoldedPolygon3D p) {
      final fId = faceIdPrefix != null && !p.faceId.contains(faceIdPrefix) ? '${faceIdPrefix}_${p.faceId}' : p.faceId;
      return CadFoldedPolygon3D(
        faceId: fId,
        vertices: p.vertices.map(transPt).toList(),
        normal: p.normal,
        color: colorOverride ?? p.color,
        drawWireframe: p.drawWireframe,
        holes: p.holes.map((h) => h.map(transPt).toList()).toList(),
        holePunchIds: p.holePunchIds,
        cutSegments: p.cutSegments.map((c) => c.map(transPt).toList()).toList(),
        boundaryLines: p.boundaryLines.map((b) => b.map(transPt).toList()).toList(),
      );
    }

    return FoldedMeshResult(
      polygons: polygons.map(transPoly).toList(),
      filletPolygons: filletPolygons.map(transPoly).toList(),
      thicknessPolygons: thicknessPolygons.map(transPoly).toList(),
      boundWidth: boundWidth,
      boundLength: boundLength,
      boundHeight: boundHeight,
      center: transPt(center),
      punchCenters3D: punchCenters3D.map((k, v) => MapEntry(k, transPt(v))),
    );
  }

  /// Transforms all vertices and normals in this mesh using [transformPt] and optional [transformNormal],
  /// with optional [colorOverride] and [faceIdPrefix].
  FoldedMeshResult transform(
    CadPoint3D Function(CadPoint3D) transformPt, {
    CadPoint3D Function(CadPoint3D)? transformNormal,
    Color? colorOverride,
    String? faceIdPrefix,
  }) {
    CadFoldedPolygon3D transPoly(CadFoldedPolygon3D p) {
      final fId = faceIdPrefix != null && !p.faceId.contains(faceIdPrefix) ? '${faceIdPrefix}_${p.faceId}' : p.faceId;
      return CadFoldedPolygon3D(
        faceId: fId,
        vertices: p.vertices.map(transformPt).toList(),
        normal: transformNormal != null ? transformNormal(p.normal) : p.normal,
        color: colorOverride ?? p.color,
        drawWireframe: p.drawWireframe,
        holes: p.holes.map((h) => h.map(transformPt).toList()).toList(),
        holePunchIds: p.holePunchIds,
        cutSegments: p.cutSegments.map((c) => c.map(transformPt).toList()).toList(),
        boundaryLines: p.boundaryLines.map((b) => b.map(transformPt).toList()).toList(),
      );
    }

    final newP = polygons.map(transPoly).toList();
    final newF = filletPolygons.map(transPoly).toList();
    final newT = thicknessPolygons.map(transPoly).toList();

    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    double minZ = double.infinity, maxZ = -double.infinity;

    void update(CadPoint3D p) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
      if (p.z < minZ) minZ = p.z;
      if (p.z > maxZ) maxZ = p.z;
    }

    for (final p in newP) {
      for (final v in p.vertices) {
        update(v);
      }
    }
    for (final p in newF) {
      for (final v in p.vertices) {
        update(v);
      }
    }
    for (final p in newT) {
      for (final v in p.vertices) {
        update(v);
      }
    }

    final hasVerts = minX.isFinite;
    final bW = hasVerts ? maxX - minX : boundWidth;
    final bL = hasVerts ? maxY - minY : boundLength;
    final bH = hasVerts ? maxZ - minZ : boundHeight;
    final c = hasVerts
        ? CadPoint3D((minX + maxX) / 2.0, (minY + maxY) / 2.0, (minZ + maxZ) / 2.0)
        : transformPt(center);

    return FoldedMeshResult(
      polygons: newP,
      filletPolygons: newF,
      thicknessPolygons: newT,
      boundWidth: bW,
      boundLength: bL,
      boundHeight: bH,
      center: c,
      punchCenters3D: punchCenters3D.map((k, v) => MapEntry(k, transformPt(v))),
    );
  }

  /// Combines this mesh with [other] into a single aggregated mesh with unified bounding box.
  /// If [preserveCenter] is true, retains this mesh's center as pivot.
  FoldedMeshResult combineWith(FoldedMeshResult other, {bool preserveCenter = false}) {
    final allP = [...polygons, ...other.polygons];
    final allF = [...filletPolygons, ...other.filletPolygons];
    final allT = [...thicknessPolygons, ...other.thicknessPolygons];

    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    double minZ = double.infinity, maxZ = -double.infinity;

    void update(CadPoint3D p) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
      if (p.z < minZ) minZ = p.z;
      if (p.z > maxZ) maxZ = p.z;
    }

    for (final p in allP) {
      for (final v in p.vertices) {
        update(v);
      }
    }
    for (final p in allF) {
      for (final v in p.vertices) {
        update(v);
      }
    }
    for (final p in allT) {
      for (final v in p.vertices) {
        update(v);
      }
    }

    if (minX == double.infinity) {
      return this;
    }

    return FoldedMeshResult(
      polygons: allP,
      filletPolygons: allF,
      thicknessPolygons: allT,
      boundWidth: maxX - minX,
      boundLength: maxY - minY,
      boundHeight: maxZ - minZ,
      center: preserveCenter ? center : CadPoint3D((minX + maxX) / 2.0, (minY + maxY) / 2.0, (minZ + maxZ) / 2.0),
      punchCenters3D: {...punchCenters3D, ...other.punchCenters3D},
    );
  }
}

/// Node in the kinematic tree
class _KinematicNode {
  final PlanarSheetFace face;
  final FoldBendLine? parentBend;
  final List<_KinematicNode> children = [];

  _KinematicNode({required this.face, this.parentBend});
}

class KinematicFoldEngine {
  /// Convenience helper returning only the list of 3D folded polygons.
  static List<CadFoldedPolygon3D> computeFold({required DsfDocument doc, double foldProgress = 1.0, bool includeFillets = false}) {
    final res = foldDocument(doc, foldProgress: foldProgress);
    return includeFillets ? res.allPolygons : res.polygons;
  }

  /// Folds a [DsfDocument] into a [FoldedMeshResult] at fold progression [foldProgress] (0.0 to 1.0).
  static FoldedMeshResult foldDocument(DsfDocument doc, {double foldProgress = 1.0, int curveResolution3D = 32, bool ensureBaseFloorAtBottom = true}) {
    final activeFaces = doc.faces.where((f) => f.isVisible).toList();
    if (activeFaces.isEmpty) {
      return const FoldedMeshResult(polygons: [], boundWidth: 0, boundLength: 0, boundHeight: 0, center: CadPoint3D(0, 0, 0));
    }

    final t = foldProgress.clamp(0.0, 1.0);

    // 1. Identify base anchor face (Root of DAG)
    PlanarSheetFace baseFace = activeFaces.firstWhere((f) => f.id == doc.baseFaceId || f.isBaseAnchor, orElse: () => activeFaces.first);

    // 2. Build the Kinematic Tree Graph (DAG) using all document bends to preserve face connectivity
    final rootNode = _buildTree(activeFaces, doc.bends, baseFace);

    // 3. Forward Kinematics traversal
    final polygons = <CadFoldedPolygon3D>[];
    final filletPolygons = <CadFoldedPolygon3D>[];
    final thicknessPolygons = <CadFoldedPolygon3D>[];
    final punchCenters3D = <String, CadPoint3D>{};
    _traverseAndFold(
      node: rootNode,
      parentTransform: TransformMatrix4.identity(),
      t: t,
      polygons: polygons,
      filletPolygons: filletPolygons,
      thicknessPolygons: thicknessPolygons,
      punches: doc.allPunches,
      cutLines: doc.cutLines,
      bends: doc.bends,
      arcs: doc.arcs,
      thicknessMm: doc.material.thicknessMm,
      edgeChamfers: doc.edgeChamfers,
      defaultEdgeChamferMm: doc.material.edgeChamferMm,
      curveResolution3D: curveResolution3D,
      punchCenters3D: punchCenters3D,
    );

    // Ensure 3D model rests upright on its bottom base floor in isometric view:
    // If other faces fold downwards into -Z relative to the base floor (meaning base floor is at the top),
    // re-traverse with inverted bend directions so the base floor is at the bottom.
    // NOTE: Trunking covers act as lids covering the fitting from above, so their flanges
    // must fold downwards into -Z over the body walls and must not be inverted.
    final isCoverDoc =
        doc.metadata['isTrunkingCover'] == true ||
        doc.metadata['isCover'] == true ||
        doc.productType.toLowerCase().contains('cover') ||
        doc.itemName.toLowerCase().contains('cover');
    final docType = '${doc.productType} ${doc.itemName}'.toLowerCase();
    final isOutsideRiser = docType.contains('outside') && (docType.contains('riser') || docType.contains('rise'));
    final shouldEnsureBaseFloorAtBottom = ensureBaseFloorAtBottom && !isCoverDoc && !isOutsideRiser;

    if (shouldEnsureBaseFloorAtBottom && t > 0.05 && polygons.isNotEmpty) {
      double baseSumZ = 0.0;
      int baseCount = 0;
      double otherSumZ = 0.0;
      int otherCount = 0;
      for (final poly in polygons) {
        final isBase = poly.faceId == baseFace.id;
        for (final v in poly.vertices) {
          if (isBase) {
            baseSumZ += v.z;
            baseCount++;
          } else {
            otherSumZ += v.z;
            otherCount++;
          }
        }
      }
      if (baseCount > 0 && otherCount > 0) {
        final avgBaseZ = baseSumZ / baseCount;
        final avgOtherZ = otherSumZ / otherCount;
        if (avgOtherZ < avgBaseZ - 1.0) {
          polygons.clear();
          filletPolygons.clear();
          thicknessPolygons.clear();
          punchCenters3D.clear();
          final invertedBends = doc.bends.map((b) => b.copyWith(direction: b.direction == BendDirection.down ? BendDirection.up : BendDirection.down)).toList();
          final uprightRootNode = _buildTree(activeFaces, invertedBends, baseFace);
          _traverseAndFold(
            node: uprightRootNode,
            parentTransform: TransformMatrix4.identity(),
            t: t,
            polygons: polygons,
            filletPolygons: filletPolygons,
            thicknessPolygons: thicknessPolygons,
            punches: doc.allPunches,
            cutLines: doc.cutLines,
            bends: invertedBends,
            arcs: doc.arcs,
            thicknessMm: doc.material.thicknessMm,
            edgeChamfers: doc.edgeChamfers,
            defaultEdgeChamferMm: doc.material.edgeChamferMm,
            curveResolution3D: curveResolution3D,
            punchCenters3D: punchCenters3D,
          );
        }
      }
    }

    // 4. Compute bounding box and center
    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    double minZ = double.infinity, maxZ = -double.infinity;

    for (final poly in polygons) {
      for (final v in poly.vertices) {
        if (v.x < minX) minX = v.x;
        if (v.x > maxX) maxX = v.x;
        if (v.y < minY) minY = v.y;
        if (v.y > maxY) maxY = v.y;
        if (v.z < minZ) minZ = v.z;
        if (v.z > maxZ) maxZ = v.z;
      }
    }

    final bw = maxX > minX ? maxX - minX : 0.0;
    final bl = maxY > minY ? maxY - minY : 0.0;
    final bh = maxZ > minZ ? maxZ - minZ : 0.0;
    final center = CadPoint3D((minX + maxX) / 2.0, (minY + maxY) / 2.0, (minZ + maxZ) / 2.0);

    return FoldedMeshResult(
      polygons: polygons,
      filletPolygons: filletPolygons,
      thicknessPolygons: thicknessPolygons,
      boundWidth: bw,
      boundLength: bl,
      boundHeight: bh,
      center: center,
      punchCenters3D: punchCenters3D,
    );
  }

  /// Builds the Kinematic DAG recursively
  static _KinematicNode _buildTree(List<PlanarSheetFace> allFaces, List<FoldBendLine> allBends, PlanarSheetFace rootFace) {
    final rootNode = _KinematicNode(face: rootFace);
    final visitedFaces = <String>{rootFace.id};

    void attachChildren(_KinematicNode currentNode) {
      final currentId = currentNode.face.id;

      // Find all bends where currentId is either parent or child
      for (final bend in allBends) {
        String? neighborId;
        if (bend.parentFaceId == currentId) {
          neighborId = bend.childFaceId;
        } else if (bend.childFaceId == currentId) {
          neighborId = bend.parentFaceId;
        }

        if (neighborId != null && neighborId.isNotEmpty && !visitedFaces.contains(neighborId)) {
          final neighborFace = allFaces.firstWhere(
            (f) => f.id == neighborId,
            orElse: () => PlanarSheetFace(id: neighborId!, vertices: const []),
          );

          if (neighborFace.vertices.isNotEmpty) {
            visitedFaces.add(neighborId);
            final childNode = _KinematicNode(face: neighborFace, parentBend: bend);
            currentNode.children.add(childNode);
            attachChildren(childNode);
          }
        }
      }
    }

    attachChildren(rootNode);

    // Ensure any disconnected visible faces are also included in the 3D model (unfolded at base level)
    for (final face in allFaces) {
      if (!visitedFaces.contains(face.id) && face.vertices.isNotEmpty) {
        visitedFaces.add(face.id);
        final unattachedNode = _KinematicNode(face: face);
        rootNode.children.add(unattachedNode);
        attachChildren(unattachedNode);
      }
    }

    return rootNode;
  }

  /// Traverses the DAG applying hierarchical forward kinematics
  static void _traverseAndFold({
    required _KinematicNode node,
    required TransformMatrix4 parentTransform,
    required double t,
    required List<CadFoldedPolygon3D> polygons,
    required List<CadFoldedPolygon3D> filletPolygons,
    required List<CadFoldedPolygon3D> thicknessPolygons,
    required List<CncPunchPrimitive> punches,
    required List<CadLineSegment> cutLines,
    required List<FoldBendLine> bends,
    List<CadArc2D> arcs = const [],
    double thicknessMm = 0.0,
    Map<String, double> edgeChamfers = const {},
    double defaultEdgeChamferMm = 0.0,
    int curveResolution3D = 32,
    Map<String, CadPoint3D>? punchCenters3D,
  }) {
    TransformMatrix4 currentTransform = parentTransform;

    if (node.parentBend != null) {
      final bend = node.parentBend!;
      // When a bend is hidden / suppressed, it remains flat (0° fold angle, unfolded)
      final effectiveTargetAngleDeg = bend.isVisible ? bend.targetAngleDeg : 0.0;
      final targetAngleRad = effectiveTargetAngleDeg * math.pi / 180.0;
      final currentAngleRad = targetAngleRad * t;

      if (currentAngleRad.abs() > 1e-6) {
        // Bend line endpoints in unfolded 2D space (clipped strictly to active face to avoid long projecting lines)
        final (p1_2d, p2_2d) = _clipBendToFace(p1: bend.p1, p2: bend.p2, faceVertices: node.face.vertices);

        // Top surface endpoints (z = 0)
        final p1Top = parentTransform.transformPoint(CadPoint3D(p1_2d.x, p1_2d.y, 0.0));
        final p2Top = parentTransform.transformPoint(CadPoint3D(p2_2d.x, p2_2d.y, 0.0));

        // Bottom surface endpoints (z = -thicknessMm)
        final p1Bot = parentTransform.transformPoint(CadPoint3D(p1_2d.x, p1_2d.y, -thicknessMm));
        final p2Bot = parentTransform.transformPoint(CadPoint3D(p2_2d.x, p2_2d.y, -thicknessMm));

        var axisVec = (p2Top - p1Top).normalized();

        // Check rotation orientation so UP always tilts towards +Z
        final mid2d = bend.midpoint;
        final childCentroid2d = node.face.centroid;
        final toChild2d = CadPoint2D(childCentroid2d.x - mid2d.x, childCentroid2d.y - mid2d.y);
        final lineDir2d = bend.unitDirection;

        // 2D cross product: lineDir x toChild
        final crossZ = lineDir2d.x * toChild2d.y - lineDir2d.y * toChild2d.x;

        // If crossZ < 0, rotating around +axis tilts +Z; if crossZ < 0, invert axis
        if (crossZ < 0) {
          axisVec = axisVec * -1.0;
        }

        // Apply signed direction: UP (+) or DOWN (-)
        final signedAngle = bend.direction == FoldDirection.up ? currentAngleRad : -currentAngleRad;

        CadPoint3D rotCenter = p1Top;

        // Generate authentic continuous solid 3D curved cylindrical bend arc fillet
        if (bend.radiusMm > 0.0 && currentAngleRad.abs() > 1e-4) {
          final rMm = math.max(0.4, bend.radiusMm);
          final nParent = parentTransform.transformVector(const CadPoint3D(0, 0, 1)).normalized();

          // Physical Sheet Metal Curvature Center:
          // UP fold (+Z): Inside surface is top (z=0, radius rMm). Curvature center at +nParent * rMm.
          // DOWN fold (-Z): Inside surface is bottom (z=-thicknessMm, radius rMm). Curvature center at -nParent * (rMm + thicknessMm).
          final CadPoint3D c1;
          final CadPoint3D inStart1;
          final CadPoint3D inStart2;
          final CadPoint3D outStart1;
          final CadPoint3D outStart2;

          if (bend.direction == FoldDirection.up) {
            c1 = p1Top + nParent * rMm;
            inStart1 = p1Top;
            inStart2 = p2Top;
            outStart1 = p1Bot;
            outStart2 = p2Bot;
          } else {
            c1 = p1Top - nParent * (rMm + thicknessMm);
            inStart1 = p1Bot;
            inStart2 = p2Bot;
            outStart1 = p1Top;
            outStart2 = p2Top;
          }
          rotCenter = c1;

          final bendLen = p1Top.distanceTo(p2Top);
          final solidIntervals = _computeSolidBendIntervals(p1_2d, p2_2d, punches);

          for (int intIdx = 0; intIdx < solidIntervals.length; intIdx++) {
            final (intervalStart, intervalEnd) = solidIntervals[intIdx];
            final intervalLen = (intervalEnd - intervalStart) * bendLen;
            if (intervalLen < 0.2) continue;
            final nLenSteps = (intervalLen / 35.0).ceil().clamp(1, 8);
            final nSteps = (curveResolution3D / 5.0).round().clamp(4, 12);

            for (int lStep = 0; lStep < nLenSteps; lStep++) {
              final t1 = intervalStart + (intervalEnd - intervalStart) * (lStep / nLenSteps);
              final t2 = intervalStart + (intervalEnd - intervalStart) * ((lStep + 1) / nLenSteps);

              final lInStart1 = inStart1 + (inStart2 - inStart1) * t1;
              final lInStart2 = inStart1 + (inStart2 - inStart1) * t2;
              final lOutStart1 = outStart1 + (outStart2 - outStart1) * t1;
              final lOutStart2 = outStart1 + (outStart2 - outStart1) * t2;

              for (int step = 0; step < nSteps; step++) {
                final a1 = step * signedAngle / nSteps;
                final a2 = (step + 1) * signedAngle / nSteps;
                final aMid = (a1 + a2) * 0.5;

                final rot1 = TransformMatrix4.rotationAroundLine(c1, axisVec, a1);
                final rot2 = TransformMatrix4.rotationAroundLine(c1, axisVec, a2);
                final rotMid = TransformMatrix4.rotationAroundLine(c1, axisVec, aMid);

                // Inside cylindrical surface (Radius R)
                final inA1 = rot1.transformPoint(lInStart1);
                final inA2 = rot1.transformPoint(lInStart2);
                final inB1 = rot2.transformPoint(lInStart1);
                final inB2 = rot2.transformPoint(lInStart2);

                // True radial normal pointing towards cylinder axis (into concave air cavity)
                final inMid = rotMid.transformPoint((lInStart1 + lInStart2) * 0.5);
                final inAxisPt = c1 + axisVec * ((inMid - c1).dot(axisVec));
                var inNorm = (inAxisPt - inMid).normalized();
                if (inNorm.length < 1e-3) inNorm = nParent;

                final inTangents = <List<CadPoint3D>>[];
                if (step == 0) inTangents.add([inA1, inA2]);
                if (step == nSteps - 1) inTangents.add([inB1, inB2]);

                filletPolygons.add(
                  CadFoldedPolygon3D(
                    faceId: 'FILLET_${bend.id}_${intIdx}_${lStep}_$step',
                    vertices: [inA1, inA2, inB2, inB1],
                    normal: inNorm,
                    color: const Color(0xFFCFD8DC), // Metallic curved fillet facet
                    tangentLines: inTangents,
                  ),
                );

                // Outside cylindrical surface (Radius R + thicknessMm) & side caps
                if (thicknessMm > 0.05) {
                  final outA1 = rot1.transformPoint(lOutStart1);
                  final outA2 = rot1.transformPoint(lOutStart2);
                  final outB1 = rot2.transformPoint(lOutStart1);
                  final outB2 = rot2.transformPoint(lOutStart2);

                  // True radial normal pointing away from cylinder axis (into convex air space)
                  final outMid = rotMid.transformPoint((lOutStart1 + lOutStart2) * 0.5);
                  final outAxisPt = c1 + axisVec * ((outMid - c1).dot(axisVec));
                  var outNorm = (outMid - outAxisPt).normalized();
                  if (outNorm.length < 1e-3) outNorm = nParent * -1.0;

                  final outTangents = <List<CadPoint3D>>[];
                  if (step == 0) outTangents.add([outA1, outA2]);
                  if (step == nSteps - 1) outTangents.add([outB1, outB2]);

                  filletPolygons.add(
                    CadFoldedPolygon3D(
                      faceId: 'FILLET_OUT_${bend.id}_${intIdx}_${lStep}_$step',
                      vertices: [outA1, outB1, outB2, outA2],
                      normal: outNorm,
                      color: const Color(0xFFB0BEC5), // Outer curved elbow facet
                      tangentLines: outTangents,
                    ),
                  );

                  // Annular Cap at start of interval (bend end or notch opening)
                  if (lStep == 0) {
                    filletPolygons.add(
                      CadFoldedPolygon3D(
                        faceId: 'FILLET_CAP1_${bend.id}_${intIdx}_$step',
                        vertices: [inA1, inB1, outB1, outA1],
                        normal: axisVec * -1.0,
                        color: const Color(0xFF78909C),
                      ),
                    );
                  }

                  // Annular Cap at end of interval (bend end or notch opening)
                  if (lStep == nLenSteps - 1) {
                    filletPolygons.add(
                      CadFoldedPolygon3D(
                        faceId: 'FILLET_CAP2_${bend.id}_${intIdx}_$step',
                        vertices: [outA2, outB2, inB2, inA2],
                        normal: axisVec,
                        color: const Color(0xFF78909C),
                      ),
                    );
                  }
                }
              }
            }
          }
        }

        // Child face transform rotates around c1 so it meets the fillet elbow tangentially
        final localRotation = TransformMatrix4.rotationAroundLine(rotCenter, axisVec, signedAngle);
        currentTransform = localRotation.multiply(parentTransform);
      }
    }

    // Transform all vertices of this face into 3D (with smooth arc expansion)
    final faceVerts = _expandFaceWithArcs(node.face.vertices, arcs);
    final vertices3D = faceVerts.map((v) => currentTransform.transformPoint(CadPoint3D(v.x, v.y, 0.0))).toList();

    // Compute surface normal
    CadPoint3D normal = const CadPoint3D(0, 0, 1);
    if (vertices3D.length >= 3) {
      for (int i = 0; i < vertices3D.length; i++) {
        final v0 = vertices3D[i];
        final v1 = vertices3D[(i + 1) % vertices3D.length];
        final v2 = vertices3D[(i + 2) % vertices3D.length];
        final d1 = v1 - v0;
        final d2 = v2 - v0;
        final cross = d1.cross(d2);
        if (cross.length > 1e-4) {
          normal = cross.normalized();
          break;
        }
      }
    }

    // Assign color by role (calibrated for light CAD background)
    Color faceColor;
    switch (node.face.role) {
      case FaceRole.baseFloor:
        faceColor = const Color(0xFFB0BEC5); // Metallic base bed
        break;
      case FaceRole.sideWall:
        faceColor = const Color(0xFFCFD8DC); // Clean metallic wall
        break;
      case FaceRole.returnFlange:
        faceColor = const Color(0xFFECEFF1); // Bright top flange highlight
        break;
      default:
        faceColor = const Color(0xFFCFD8DC);
    }

    // Filter punches belonging to this face (fast bounding box check first)
    final facePunches = punches.where((p) => _punchOverlapsFace(p, node.face.vertices)).toList();

    // Transform punch holes belonging to this face (including edge-overlapping holes)
    final holes3D = <List<CadPoint3D>>[];
    final holePunchIds = <String>[];
    for (final punch in facePunches) {
      if (punchCenters3D != null) {
        punchCenters3D[punch.id] = currentTransform.transformPoint(CadPoint3D(punch.center.x, punch.center.y, 0.0));
      }
      final hole2D = punch.toPolygon(circleSegments: curveResolution3D);
      if (hole2D.length >= 3) {
        holes3D.add(hole2D.map((p) => currentTransform.transformPoint(CadPoint3D(p.x, p.y, 0.0))).toList());
        holePunchIds.add(punch.id);
      }
    }
    // Fallback: If no punch primitives match but the face has stored hole loops (e.g. from imported .dsf), include them
    if (facePunches.isEmpty && node.face.holes.isNotEmpty) {
      for (final hole2D in node.face.holes) {
        if (hole2D.length >= 3) {
          holes3D.add(hole2D.map((p) => currentTransform.transformPoint(CadPoint3D(p.x, p.y, 0.0))).toList());
        }
      }
    }

    // Transform cut line segments belonging to this face into 3D
    final cutSegments3D = <List<CadPoint3D>>[];
    for (final cut in cutLines) {
      final clipped = _clipSegmentToPolygon(cut.p1, cut.p2, node.face.vertices);
      for (final seg in clipped) {
        if (seg.$1.distanceTo(seg.$2) > 0.4) {
          cutSegments3D.add([
            currentTransform.transformPoint(CadPoint3D(seg.$1.x, seg.$1.y, 0.0)),
            currentTransform.transformPoint(CadPoint3D(seg.$2.x, seg.$2.y, 0.0)),
          ]);
        }
      }
    }

    // SS1 Fix: Generate true exposed boundary lines for top surface (excluding bend seams and clipped against holes)
    final numVerts = faceVerts.length;
    final boundaryLines3D = <List<CadPoint3D>>[];
    for (int i = 0; i < numVerts; i++) {
      final pA = faceVerts[i];
      final pB = faceVerts[(i + 1) % numVerts];
      final nonBendSegs = _clipSegmentOutsideBends(pA, pB, bends);
      for (final (nbA, nbB) in nonBendSegs) {
        final exposedSegments = _clipSegmentOutsidePunches(nbA, nbB, facePunches);
        for (final seg in exposedSegments) {
          if (seg.$1.distanceTo(seg.$2) > 0.3) {
            boundaryLines3D.add([
              currentTransform.transformPoint(CadPoint3D(seg.$1.x, seg.$1.y, 0.0)),
              currentTransform.transformPoint(CadPoint3D(seg.$2.x, seg.$2.y, 0.0)),
            ]);
          }
        }
      }
    }

    polygons.add(
      CadFoldedPolygon3D(
        faceId: node.face.id,
        vertices: vertices3D,
        normal: normal,
        color: faceColor,
        holes: holes3D,
        holePunchIds: holePunchIds,
        cutSegments: cutSegments3D,
        boundaryLines: boundaryLines3D,
      ),
    );

    // Apply Physical Sheet Metal Thickness
    if (thicknessMm > 0.05) {
      final vertices3DBot = faceVerts.reversed.map((v) => currentTransform.transformPoint(CadPoint3D(v.x, v.y, -thicknessMm))).toList();

      final holes3DBot = <List<CadPoint3D>>[];
      final holePunchIdsBot = <String>[];
      for (final punch in facePunches) {
        final hole2D = punch.toPolygon(circleSegments: curveResolution3D);
        if (hole2D.length >= 3) {
          holes3DBot.add(hole2D.reversed.map((p) => currentTransform.transformPoint(CadPoint3D(p.x, p.y, -thicknessMm))).toList());
          holePunchIdsBot.add(punch.id);
        }
      }
      if (facePunches.isEmpty && node.face.holes.isNotEmpty) {
        for (final hole2D in node.face.holes) {
          if (hole2D.length >= 3) {
            holes3DBot.add(hole2D.reversed.map((p) => currentTransform.transformPoint(CadPoint3D(p.x, p.y, -thicknessMm))).toList());
          }
        }
      }

      final boundaryLines3DBot = <List<CadPoint3D>>[];
      for (int i = 0; i < numVerts; i++) {
        final pA = faceVerts[i];
        final pB = faceVerts[(i + 1) % numVerts];
        final nonBendSegs = _clipSegmentOutsideBends(pA, pB, bends);
        for (final (nbA, nbB) in nonBendSegs) {
          final exposedSegments = _clipSegmentOutsidePunches(nbA, nbB, facePunches);
          for (final seg in exposedSegments) {
            if (seg.$1.distanceTo(seg.$2) > 0.3) {
              boundaryLines3DBot.add([
                currentTransform.transformPoint(CadPoint3D(seg.$1.x, seg.$1.y, -thicknessMm)),
                currentTransform.transformPoint(CadPoint3D(seg.$2.x, seg.$2.y, -thicknessMm)),
              ]);
            }
          }
        }
      }

      thicknessPolygons.add(
        CadFoldedPolygon3D(
          faceId: '${node.face.id}_BOT',
          vertices: vertices3DBot,
          normal: normal * -1.0,
          color: faceColor,
          holes: holes3DBot,
          holePunchIds: holePunchIdsBot,
          boundaryLines: boundaryLines3DBot,
        ),
      );

      // Fix 2: Skip bore wall generation for thin sheets (< 1.0 mm).
      // At sub-1mm thickness the bore walls are sub-pixel on screen and cause depth-sorting
      // artifacts that make the top face appear transparent.
      if (thicknessMm >= 1.0) {
        // SS2 Fix: Solid Pass-Through Hole Bore Walls with exact outside-punch segment clipping
        for (final punch in facePunches) {
          final hole2D = punch.toPolygon(circleSegments: curveResolution3D);
          if (hole2D.length >= 3) {
            final punchMaxRad = math.max(punch.diameterMm / 2.0, math.max(punch.widthMm, punch.lengthMm) / 2.0);
            final potentialOverlaps = facePunches.where((other) {
              if (other.id == punch.id) return false;
              final otherMaxRad = math.max(other.diameterMm / 2.0, math.max(other.widthMm, other.lengthMm) / 2.0);
              return punch.center.distanceTo(other.center) <= (punchMaxRad + otherMaxRad + 0.5);
            }).toList();

            for (int i = 0; i < hole2D.length; i++) {
              final p1 = hole2D[i];
              final p2 = hole2D[(i + 1) % hole2D.length];

              // 1. Clip punch segment against this face polygon so it stays 100% on this face
              final clippedSegments = _clipSegmentToPolygon(p1, p2, faceVerts);
              for (int segIdx = 0; segIdx < clippedSegments.length; segIdx++) {
                final (faceSegA, faceSegB) = clippedSegments[segIdx];
                if (faceSegA.distanceTo(faceSegB) < 0.2) continue;

                // 2. SS2 Fix: Clip segment OUTSIDE any overlapping punches so bore walls NEVER cut into the void!
                final outsideSegments = potentialOverlaps.isEmpty ? [(faceSegA, faceSegB)] : _clipSegmentOutsidePunches(faceSegA, faceSegB, potentialOverlaps);

                for (int outIdx = 0; outIdx < outsideSegments.length; outIdx++) {
                  final (segA, segB) = outsideSegments[outIdx];
                  if (segA.distanceTo(segB) < 0.2) continue;

                  final topA = currentTransform.transformPoint(CadPoint3D(segA.x, segA.y, 0.0));
                  final topB = currentTransform.transformPoint(CadPoint3D(segB.x, segB.y, 0.0));
                  final botB = currentTransform.transformPoint(CadPoint3D(segB.x, segB.y, -thicknessMm));
                  final botA = currentTransform.transformPoint(CadPoint3D(segA.x, segA.y, -thicknessMm));

                  var boreNorm = (topB - topA).cross(botA - topA).normalized();
                  if (boreNorm.length < 1e-3) {
                    boreNorm = (botB - topA).cross(botA - topB).normalized();
                  }

                  thicknessPolygons.add(
                    CadFoldedPolygon3D(
                      faceId: 'BORE_${node.face.id}_${punch.id}_${i}_${segIdx}_$outIdx',
                      vertices: [topA, topB, botB, botA],
                      normal: boreNorm.length > 0 ? boreNorm : const CadPoint3D(0, 1, 0),
                      color: const Color(0xFF546E7A), // Machined inner hole bore wall
                    ),
                  );
                }
              }
            }
          }
        }
      } // end if (thicknessMm >= 1.0) — bore walls only for thick sheets

      // SS3 & SS4 Fix: Side thickness rim quads and 45° edge chamfers with corner mitering and bend relief
      // 1. Precompute per-edge metadata
      final isEdgeBendList = List<bool>.filled(numVerts, false);
      final edgeChamferList = List<double>.filled(numVerts, 0.0);
      final edgeUList = List<CadPoint2D>.filled(numVerts, const CadPoint2D(0, 0));
      final edgeInList = List<CadPoint2D>.filled(numVerts, const CadPoint2D(0, 0));

      for (int i = 0; i < numVerts; i++) {
        final pA = faceVerts[i];
        final pB = faceVerts[(i + 1) % numVerts];
        final isBend = _isEdgeBend(pA, pB, bends) || _clipSegmentOutsideBends(pA, pB, bends).isEmpty;
        isEdgeBendList[i] = isBend;

        if (!isBend) {
          final segLen = pA.distanceTo(pB);
          if (segLen > 0.5) {
            final dx = pB.x - pA.x;
            final dy = pB.y - pA.y;
            edgeUList[i] = CadPoint2D(dx / segLen, dy / segLen);

            var inX = -dy / segLen;
            var inY = dx / segLen;
            final pMid = CadPoint2D((pA.x + pB.x) * 0.5, (pA.y + pB.y) * 0.5);
            final probe = CadPoint2D(pMid.x + inX * 0.1, pMid.y + inY * 0.1);
            if (!_isPointInPoly(probe, faceVerts)) {
              inX = -inX;
              inY = -inY;
            }
            edgeInList[i] = CadPoint2D(inX, inY);

            final edgeKey = '${node.face.id}_$i';
            double c = edgeChamfers[edgeKey] ?? edgeChamfers['ALL'] ?? defaultEdgeChamferMm;
            final maxChamfer = math.min(thicknessMm * 0.45, segLen * 0.4);
            c = c.clamp(0.0, maxChamfer);
            if (c > 0.05) {
              edgeChamferList[i] = c;
            }
          }
        }
      }

      // 2. Precompute per-vertex metadata: near bend and top corner miter point
      final isVNearBendList = List<bool>.filled(numVerts, false);
      final topCornerList = List<CadPoint2D?>.filled(numVerts, null);

      for (int i = 0; i < numVerts; i++) {
        final V = faceVerts[i];
        final nearBend = _isPointNearBend(V, bends);
        isVNearBendList[i] = nearBend;

        final prev = (i - 1 + numVerts) % numVerts;
        final curr = i;
        final cPrev = edgeChamferList[prev];
        final cCurr = edgeChamferList[curr];

        if (nearBend) {
          topCornerList[i] = V;
        } else if (cPrev > 0.0 && cCurr > 0.0) {
          topCornerList[i] = _computeMiterPoint(V, edgeInList[prev], edgeInList[curr], edgeUList[prev], edgeUList[curr], cPrev, cCurr);
        } else if (cCurr > 0.0) {
          topCornerList[i] = CadPoint2D(V.x + edgeInList[curr].x * cCurr, V.y + edgeInList[curr].y * cCurr);
        } else if (cPrev > 0.0) {
          topCornerList[i] = CadPoint2D(V.x + edgeInList[prev].x * cPrev, V.y + edgeInList[prev].y * cPrev);
        } else {
          topCornerList[i] = V;
        }
      }

      // 3. Emit chamfers and rims for each exposed edge
      for (int i = 0; i < numVerts; i++) {
        if (isEdgeBendList[i]) continue;

        final pA = faceVerts[i];
        final pB = faceVerts[(i + 1) % numVerts];
        final segLen = pA.distanceTo(pB);
        final c = edgeChamferList[i];
        final u = edgeUList[i];
        final inVec = edgeInList[i];
        final next = (i + 1) % numVerts;

        if (c <= 0.05 || segLen <= 0.5) {
          // Standard unchamfered vertical rim
          final vTopA = currentTransform.transformPoint(CadPoint3D(pA.x, pA.y, 0.0));
          final vTopB = currentTransform.transformPoint(CadPoint3D(pB.x, pB.y, 0.0));
          final vBotB = currentTransform.transformPoint(CadPoint3D(pB.x, pB.y, -thicknessMm));
          final vBotA = currentTransform.transformPoint(CadPoint3D(pA.x, pA.y, -thicknessMm));

          final outVec = currentTransform.transformVector(CadPoint3D(-inVec.x, -inVec.y, 0.0)).normalized();
          var rimNorm = (vBotA - vTopA).cross(vTopB - vTopA).normalized();
          if (rimNorm.length < 1e-3) {
            rimNorm = outVec.length > 1e-3 ? outVec : const CadPoint3D(1, 0, 0);
          } else if (outVec.length > 1e-3 && rimNorm.dot(outVec) < 0) {
            rimNorm = rimNorm * -1.0;
          }

          thicknessPolygons.add(
            CadFoldedPolygon3D(faceId: 'RIM_${node.face.id}_$i', vertices: [vTopA, vTopB, vBotB, vBotA], normal: rimNorm, color: const Color(0xFF78909C)),
          );
        } else {
          final nearBendA = isVNearBendList[i];
          final nearBendB = isVNearBendList[next];

          final dTransA = nearBendA ? math.min(c * 2.0, segLen * 0.35) : 0.0;
          final dTransB = nearBendB ? math.min(c * 2.0, segLen * 0.35) : 0.0;

          final pTransA = nearBendA ? CadPoint2D(pA.x + u.x * dTransA, pA.y + u.y * dTransA) : pA;
          final pTransB = nearBendB ? CadPoint2D(pB.x - u.x * dTransB, pB.y - u.y * dTransB) : pB;

          // A. Lead-in Taper from bend at start
          if (nearBendA && dTransA > 0.1) {
            final tTop0 = currentTransform.transformPoint(CadPoint3D(pA.x, pA.y, 0.0));
            final tTop1 = currentTransform.transformPoint(CadPoint3D(pTransA.x + inVec.x * c, pTransA.y + inVec.y * c, 0.0));
            final tMid1 = currentTransform.transformPoint(CadPoint3D(pTransA.x, pTransA.y, -c));
            final tBot1 = currentTransform.transformPoint(CadPoint3D(pTransA.x, pTransA.y, -thicknessMm));
            final tBot0 = currentTransform.transformPoint(CadPoint3D(pA.x, pA.y, -thicknessMm));

            var tNorm = (tMid1 - tTop0).cross(tTop1 - tTop0).normalized();
            if (tNorm.length < 1e-3) tNorm = const CadPoint3D(0, 0, 1);
            thicknessPolygons.add(
              CadFoldedPolygon3D(faceId: 'CHAMFER_${node.face.id}_${i}_taperA', vertices: [tTop0, tTop1, tMid1], normal: tNorm, color: const Color(0xFFB0BEC5)),
            );

            var rNorm = (tBot0 - tTop0).cross(tMid1 - tTop0).normalized();
            if (rNorm.length < 1e-3) rNorm = const CadPoint3D(1, 0, 0);
            thicknessPolygons.add(
              CadFoldedPolygon3D(
                faceId: 'RIM_${node.face.id}_${i}_taperA',
                vertices: [tTop0, tMid1, tBot1, tBot0],
                normal: rNorm,
                color: const Color(0xFF78909C),
              ),
            );
          }

          // B. Main Chamfer & Rim Section with Corner Mitering
          final topPtA = nearBendA ? CadPoint2D(pTransA.x + inVec.x * c, pTransA.y + inVec.y * c) : topCornerList[i]!;
          final topPtB = nearBendB ? CadPoint2D(pTransB.x + inVec.x * c, pTransB.y + inVec.y * c) : topCornerList[next]!;

          final vTopA = currentTransform.transformPoint(CadPoint3D(topPtA.x, topPtA.y, 0.0));
          final vTopB = currentTransform.transformPoint(CadPoint3D(topPtB.x, topPtB.y, 0.0));
          final vMidA = currentTransform.transformPoint(CadPoint3D(pTransA.x, pTransA.y, -c));
          final vMidB = currentTransform.transformPoint(CadPoint3D(pTransB.x, pTransB.y, -c));
          final vBotB = currentTransform.transformPoint(CadPoint3D(pTransB.x, pTransB.y, -thicknessMm));
          final vBotA = currentTransform.transformPoint(CadPoint3D(pTransA.x, pTransA.y, -thicknessMm));

          var chNorm = (vMidA - vTopA).cross(vTopB - vTopA).normalized();
          if (chNorm.length < 1e-3) chNorm = const CadPoint3D(0, 0, 1);
          thicknessPolygons.add(
            CadFoldedPolygon3D(
              faceId: 'CHAMFER_${node.face.id}_$i',
              vertices: [vTopA, vTopB, vMidB, vMidA],
              normal: chNorm,
              color: const Color(0xFFB0BEC5), // Bright beveled steel chamfer highlight
            ),
          );

          final outVec = currentTransform.transformVector(CadPoint3D(-inVec.x, -inVec.y, 0.0)).normalized();
          var rimNorm = (vBotA - vMidA).cross(vMidB - vMidA).normalized();
          if (rimNorm.length < 1e-3) {
            rimNorm = outVec.length > 1e-3 ? outVec : const CadPoint3D(1, 0, 0);
          } else if (outVec.length > 1e-3 && rimNorm.dot(outVec) < 0) {
            rimNorm = rimNorm * -1.0;
          }
          thicknessPolygons.add(
            CadFoldedPolygon3D(
              faceId: 'RIM_${node.face.id}_$i',
              vertices: [vMidA, vMidB, vBotB, vBotA],
              normal: rimNorm,
              color: const Color(0xFF78909C), // Steel cut edge rim
            ),
          );

          // C. Lead-out Taper to bend at end
          if (nearBendB && dTransB > 0.1) {
            final tTop0 = currentTransform.transformPoint(CadPoint3D(pTransB.x + inVec.x * c, pTransB.y + inVec.y * c, 0.0));
            final tTop1 = currentTransform.transformPoint(CadPoint3D(pB.x, pB.y, 0.0));
            final tMid0 = currentTransform.transformPoint(CadPoint3D(pTransB.x, pTransB.y, -c));
            final tBot0 = currentTransform.transformPoint(CadPoint3D(pTransB.x, pTransB.y, -thicknessMm));
            final tBot1 = currentTransform.transformPoint(CadPoint3D(pB.x, pB.y, -thicknessMm));

            var tNorm = (tMid0 - tTop0).cross(tTop1 - tTop0).normalized();
            if (tNorm.length < 1e-3) tNorm = const CadPoint3D(0, 0, 1);
            thicknessPolygons.add(
              CadFoldedPolygon3D(faceId: 'CHAMFER_${node.face.id}_${i}_taperB', vertices: [tTop0, tTop1, tMid0], normal: tNorm, color: const Color(0xFFB0BEC5)),
            );

            var rNorm = (tBot0 - tMid0).cross(tTop1 - tMid0).normalized();
            if (rNorm.length < 1e-3) rNorm = const CadPoint3D(1, 0, 0);
            thicknessPolygons.add(
              CadFoldedPolygon3D(
                faceId: 'RIM_${node.face.id}_${i}_taperB',
                vertices: [tMid0, tTop1, tBot1, tBot0],
                normal: rNorm,
                color: const Color(0xFF78909C),
              ),
            );
          }

          // D. End cap closure if meeting an unchamfered edge
          final prev = (i - 1 + numVerts) % numVerts;
          if (!nearBendA && edgeChamferList[prev] <= 0.0) {
            final cTop = vTopA;
            final cMid = vMidA;
            final cOrig = currentTransform.transformPoint(CadPoint3D(pA.x, pA.y, 0.0));
            var capNorm = (cMid - cTop).cross(cOrig - cTop).normalized();
            if (capNorm.length < 1e-3) capNorm = const CadPoint3D(0, 0, 1);
            thicknessPolygons.add(
              CadFoldedPolygon3D(
                faceId: 'CHAMFER_CAP_${node.face.id}_${i}_start',
                vertices: [cTop, cOrig, cMid],
                normal: capNorm,
                color: const Color(0xFFB0BEC5),
              ),
            );
          }

          if (!nearBendB && edgeChamferList[next] <= 0.0) {
            final cTop = vTopB;
            final cMid = vMidB;
            final cOrig = currentTransform.transformPoint(CadPoint3D(pB.x, pB.y, 0.0));
            var capNorm = (cOrig - cTop).cross(cMid - cTop).normalized();
            if (capNorm.length < 1e-3) capNorm = const CadPoint3D(0, 0, 1);
            thicknessPolygons.add(
              CadFoldedPolygon3D(
                faceId: 'CHAMFER_CAP_${node.face.id}_${i}_end',
                vertices: [cTop, cMid, cOrig],
                normal: capNorm,
                color: const Color(0xFFB0BEC5),
              ),
            );
          }
        }
      }
    }

    // Recurse into children
    for (final child in node.children) {
      _traverseAndFold(
        node: child,
        parentTransform: currentTransform,
        t: t,
        polygons: polygons,
        filletPolygons: filletPolygons,
        thicknessPolygons: thicknessPolygons,
        punches: punches,
        cutLines: cutLines,
        bends: bends,
        arcs: arcs,
        thicknessMm: thicknessMm,
        edgeChamfers: edgeChamfers,
        defaultEdgeChamferMm: defaultEdgeChamferMm,
        curveResolution3D: curveResolution3D,
        punchCenters3D: punchCenters3D,
      );
    }
  }

  static bool _punchOverlapsFace(CncPunchPrimitive punch, List<CadPoint2D> faceVertices) {
    if (faceVertices.length < 3) return false;

    // Fast Bounding Box check:
    double minX = faceVertices[0].x, maxX = faceVertices[0].x;
    double minY = faceVertices[0].y, maxY = faceVertices[0].y;
    for (int i = 1; i < faceVertices.length; i++) {
      final v = faceVertices[i];
      if (v.x < minX) minX = v.x;
      if (v.x > maxX) maxX = v.x;
      if (v.y < minY) minY = v.y;
      if (v.y > maxY) maxY = v.y;
    }

    final radius = math.max(punch.diameterMm / 2.0, math.max(punch.widthMm, punch.lengthMm) / 2.0);

    if (punch.center.x < minX - radius || punch.center.x > maxX + radius || punch.center.y < minY - radius || punch.center.y > maxY + radius) {
      return false;
    }

    // 1. Center inside face
    if (_isPointInPoly(punch.center, faceVertices)) return true;

    // 2. Any punch perimeter point inside face
    final poly = punch.toPolygon();
    for (final pt in poly) {
      if (_isPointInPoly(pt, faceVertices)) return true;
    }

    // 3. Proximity to face boundary edges
    for (int i = 0; i < faceVertices.length; i++) {
      final p1 = faceVertices[i];
      final p2 = faceVertices[(i + 1) % faceVertices.length];
      final dist = _distToSegment(punch.center, p1, p2);
      if (dist <= radius) return true;
    }

    return false;
  }

  static double _distToSegment(CadPoint2D p, CadPoint2D a, CadPoint2D b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final lenSq = dx * dx + dy * dy;
    if (lenSq < 1e-6) return p.distanceTo(a);
    final t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq;
    final clampedT = t.clamp(0.0, 1.0);
    final proj = CadPoint2D(a.x + clampedT * dx, a.y + clampedT * dy);
    return p.distanceTo(proj);
  }

  static double _distToInfiniteLine(CadPoint2D p, CadPoint2D a, CadPoint2D b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-6) return p.distanceTo(a);
    return ((p.x - a.x) * dy - (p.y - a.y) * dx).abs() / len;
  }

  static bool _isPointInPoly(CadPoint2D pt, List<CadPoint2D> poly) {
    if (poly.length < 3) return false;
    bool inside = false;
    for (int i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final xi = poly[i].x, yi = poly[i].y;
      final xj = poly[j].x, yj = poly[j].y;
      final intersect = ((yi > pt.y) != (yj > pt.y)) && (pt.x < (xj - xi) * (pt.y - yi) / (yj - yi) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  static bool _isPointInPunch(CadPoint2D pt, CncPunchPrimitive p) {
    if (p.type == PunchType.roundHole) {
      final r = p.diameterMm / 2.0;
      return pt.distanceTo(p.center) < (r - 0.05);
    }
    return _isPointInPoly(pt, p.toPolygon());
  }

  static List<(CadPoint2D, CadPoint2D)> _clipSegmentOutsideBends(CadPoint2D pA, CadPoint2D pB, List<FoldBendLine> bends) {
    final dx = pB.x - pA.x;
    final dy = pB.y - pA.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 0.2) return [];
    if (bends.isEmpty) return [(pA, pB)];

    final tList = <double>[0.0, 1.0];
    for (final b in bends) {
      final distA = _distToInfiniteLine(pA, b.p1, b.p2);
      final distB = _distToInfiniteLine(pB, b.p1, b.p2);
      if (distA < 0.8 && distB < 0.8) {
        final bLenSq = dx * dx + dy * dy;
        final t1 = ((b.p1.x - pA.x) * dx + (b.p1.y - pA.y) * dy) / bLenSq;
        final t2 = ((b.p2.x - pA.x) * dx + (b.p2.y - pA.y) * dy) / bLenSq;
        final minT = math.min(t1, t2).clamp(0.0, 1.0);
        final maxT = math.max(t1, t2).clamp(0.0, 1.0);
        if (minT > 1e-4 && minT < 1.0 - 1e-4) tList.add(minT);
        if (maxT > 1e-4 && maxT < 1.0 - 1e-4) tList.add(maxT);
      }
    }

    tList.sort();
    final res = <(CadPoint2D, CadPoint2D)>[];
    for (int i = 0; i < tList.length - 1; i++) {
      final tA = tList[i];
      final tB = tList[i + 1];
      if ((tB - tA) * len < 0.3) continue;

      final midT = (tA + tB) / 2.0;
      final midPt = CadPoint2D(pA.x + midT * dx, pA.y + midT * dy);
      bool isBend = false;
      for (final b in bends) {
        if (_distToInfiniteLine(midPt, b.p1, b.p2) < 0.8 && _distToSegment(midPt, b.p1, b.p2) < 0.8) {
          isBend = true;
          break;
        }
      }
      if (!isBend) {
        res.add((CadPoint2D(pA.x + tA * dx, pA.y + tA * dy), CadPoint2D(pA.x + tB * dx, pA.y + tB * dy)));
      }
    }
    return res;
  }

  static bool _isEdgeBend(CadPoint2D pA, CadPoint2D pB, List<FoldBendLine> bends) {
    for (final b in bends) {
      final distA = _distToInfiniteLine(pA, b.p1, b.p2);
      final distB = _distToInfiniteLine(pB, b.p1, b.p2);
      if (distA < 0.8 && distB < 0.8) {
        final pMid = CadPoint2D((pA.x + pB.x) * 0.5, (pA.y + pB.y) * 0.5);
        if (_distToSegment(pMid, b.p1, b.p2) < 1.0) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _isPointNearBend(CadPoint2D pt, List<FoldBendLine> bends, {double tolerance = 0.5}) {
    for (final b in bends) {
      if (_distToSegment(pt, b.p1, b.p2) < tolerance) {
        return true;
      }
    }
    return false;
  }

  static List<(CadPoint2D, CadPoint2D)> _clipSegmentOutsidePunches(CadPoint2D p1, CadPoint2D p2, List<CncPunchPrimitive> punches) {
    final dx = p2.x - p1.x;
    final dy = p2.y - p1.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 0.2) return [];
    if (punches.isEmpty) return [(p1, p2)];

    final tList = <double>[0.0, 1.0];

    for (final punch in punches) {
      final poly = punch.toPolygon();
      if (poly.length < 3) continue;
      for (int i = 0; i < poly.length; i++) {
        final a = poly[i];
        final b = poly[(i + 1) % poly.length];
        final denom = (b.y - a.y) * dx - (b.x - a.x) * dy;
        if (denom.abs() > 1e-8) {
          final t = ((b.x - a.x) * (p1.y - a.y) - (b.y - a.y) * (p1.x - a.x)) / denom;
          final u = (dx * (p1.y - a.y) - dy * (p1.x - a.x)) / denom;
          if (t > 1e-4 && t < 1.0 - 1e-4 && u >= -1e-4 && u <= 1.0 + 1e-4) {
            tList.add(t);
          }
        }
      }
    }

    tList.sort();
    final res = <(CadPoint2D, CadPoint2D)>[];

    for (int i = 0; i < tList.length - 1; i++) {
      final tA = tList[i];
      final tB = tList[i + 1];
      if ((tB - tA) * len < 0.2) continue;

      final midT = (tA + tB) / 2.0;
      final midPt = CadPoint2D(p1.x + midT * dx, p1.y + midT * dy);
      bool insideAny = false;
      for (final punch in punches) {
        if (_isPointInPunch(midPt, punch)) {
          insideAny = true;
          break;
        }
      }
      if (!insideAny) {
        final ptA = CadPoint2D(p1.x + tA * dx, p1.y + tA * dy);
        final ptB = CadPoint2D(p1.x + tB * dx, p1.y + tB * dy);
        res.add((ptA, ptB));
      }
    }

    return res;
  }

  static CadPoint2D _computeMiterPoint(CadPoint2D V, CadPoint2D inPrev, CadPoint2D inCurr, CadPoint2D uPrev, CadPoint2D uCurr, double cPrev, double cCurr) {
    final p1 = CadPoint2D(V.x + inPrev.x * cPrev, V.y + inPrev.y * cPrev);
    final p2 = CadPoint2D(V.x + inCurr.x * cCurr, V.y + inCurr.y * cCurr);

    final denom = uPrev.x * uCurr.y - uPrev.y * uCurr.x;
    if (denom.abs() > 0.1) {
      final t = ((p2.x - p1.x) * uCurr.y - (p2.y - p1.y) * uCurr.x) / denom;
      final miterX = p1.x + uPrev.x * t;
      final miterY = p1.y + uPrev.y * t;
      final miterPt = CadPoint2D(miterX, miterY);
      final maxDist = math.max(cPrev, cCurr) * 2.5;
      if (miterPt.distanceTo(V) <= maxDist) {
        return miterPt;
      }
    }

    return CadPoint2D(V.x + inPrev.x * cPrev + inCurr.x * cCurr, V.y + inPrev.y * cPrev + inCurr.y * cCurr);
  }

  static List<(CadPoint2D, CadPoint2D)> _clipSegmentToPolygon(CadPoint2D p1, CadPoint2D p2, List<CadPoint2D> poly) {
    if (poly.length < 3) return [];
    final dx = p2.x - p1.x;
    final dy = p2.y - p1.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 0.4) return [];

    final tList = <double>[0.0, 1.0];

    for (int i = 0; i < poly.length; i++) {
      final a = poly[i];
      final b = poly[(i + 1) % poly.length];
      final denom = (b.y - a.y) * dx - (b.x - a.x) * dy;
      if (denom.abs() > 1e-8) {
        final t = ((b.x - a.x) * (p1.y - a.y) - (b.y - a.y) * (p1.x - a.x)) / denom;
        final u = (dx * (p1.y - a.y) - dy * (p1.x - a.x)) / denom;
        if (t > 1e-4 && t < 1.0 - 1e-4 && u >= -1e-4 && u <= 1.0 + 1e-4) {
          tList.add(t);
        }
      }
    }

    tList.sort();
    final res = <(CadPoint2D, CadPoint2D)>[];

    for (int i = 0; i < tList.length - 1; i++) {
      final tA = tList[i];
      final tB = tList[i + 1];
      if ((tB - tA) * len < 0.2) continue;

      final midT = (tA + tB) / 2.0;
      final midPt = CadPoint2D(p1.x + midT * dx, p1.y + midT * dy);
      if (_isPointInPoly(midPt, poly)) {
        final ptA = CadPoint2D(p1.x + tA * dx, p1.y + tA * dy);
        final ptB = CadPoint2D(p1.x + tB * dx, p1.y + tB * dy);
        res.add((ptA, ptB));
      }
    }

    return res;
  }

  /// Clips a bend line [p1, p2] to the active portion that touches or bounds [faceVertices].
  /// Prevents bend fillets from extending into empty space when a part has been cut with a laser cut line.
  static (CadPoint2D, CadPoint2D) _clipBendToFace({required CadPoint2D p1, required CadPoint2D p2, required List<CadPoint2D> faceVertices}) {
    if (faceVertices.length < 3) return (p1, p2);
    final dx = p2.x - p1.x;
    final dy = p2.y - p1.y;
    final lenSq = dx * dx + dy * dy;
    if (lenSq < 1e-4) return (p1, p2);
    final len = math.sqrt(lenSq);

    double minT = 1.0;
    double maxT = 0.0;
    bool foundAny = false;

    // Check all vertices of the face that lie on or extremely close to the bend line
    for (final v in faceVertices) {
      final dist = ((v.x - p1.x) * dy - (v.y - p1.y) * dx).abs() / len;
      if (dist < 0.6) {
        final t = ((v.x - p1.x) * dx + (v.y - p1.y) * dy) / lenSq;
        if (t < minT) minT = t;
        if (t > maxT) maxT = t;
        foundAny = true;
      }
    }

    // Check intersections of face polygon edges with the bend line
    final numVerts = faceVertices.length;
    for (int i = 0; i < numVerts; i++) {
      final a = faceVertices[i];
      final b = faceVertices[(i + 1) % numVerts];
      final denom = (b.y - a.y) * dx - (b.x - a.x) * dy;
      if (denom.abs() > 1e-8) {
        final t = ((b.x - a.x) * (p1.y - a.y) - (b.y - a.y) * (p1.x - a.x)) / denom;
        final u = (dx * (p1.y - a.y) - dy * (p1.x - a.x)) / denom;
        if (u >= -1e-4 && u <= 1.0 + 1e-4) {
          if (t < minT) minT = t;
          if (t > maxT) maxT = t;
          foundAny = true;
        }
      }
    }

    if (!foundAny || maxT <= minT + 1e-4) {
      return (p1, p2);
    }

    final clampedMinT = minT.clamp(0.0, 1.0);
    final clampedMaxT = maxT.clamp(0.0, 1.0);
    if (clampedMaxT <= clampedMinT + 1e-4) {
      return (p1, p2);
    }

    final clippedP1 = CadPoint2D(p1.x + dx * clampedMinT, p1.y + dy * clampedMinT);
    final clippedP2 = CadPoint2D(p1.x + dx * clampedMaxT, p1.y + dy * clampedMaxT);
    return (clippedP1, clippedP2);
  }

  /// Computes intervals [tStart, tEnd] along bend line [p1, p2] where the sheet
  /// metal is solid (i.e. not notched/cut open by any punch holes).
  static List<(double, double)> _computeSolidBendIntervals(CadPoint2D p1, CadPoint2D p2, List<CncPunchPrimitive> punches) {
    final dx = p2.x - p1.x;
    final dy = p2.y - p1.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 0.5) return [(0.0, 1.0)];

    final minX = math.min(p1.x, p2.x) - 40.0;
    final maxX = math.max(p1.x, p2.x) + 40.0;
    final minY = math.min(p1.y, p2.y) - 40.0;
    final maxY = math.max(p1.y, p2.y) + 40.0;

    final candidatePunches = punches.where((p) => p.center.x >= minX && p.center.x <= maxX && p.center.y >= minY && p.center.y <= maxY).toList();

    if (candidatePunches.isEmpty) return [(0.0, 1.0)];

    final tSplitList = <double>[0.0, 1.0];

    for (final punch in candidatePunches) {
      if (punch.type == PunchType.roundHole) {
        final r = punch.diameterMm / 2.0;
        final c = punch.center;
        // Intersection of segment p1 + t*(p2 - p1) with circle (c, r)
        final fx = p1.x - c.x;
        final fy = p1.y - c.y;
        final a = dx * dx + dy * dy;
        final b = 2.0 * (fx * dx + fy * dy);
        final cc = fx * fx + fy * fy - r * r;
        final discr = b * b - 4.0 * a * cc;
        if (discr >= 0) {
          final sqrtD = math.sqrt(discr);
          final tA = (-b - sqrtD) / (2.0 * a);
          final tB = (-b + sqrtD) / (2.0 * a);
          if (tA > 1e-4 && tA < 1.0 - 1e-4) tSplitList.add(tA);
          if (tB > 1e-4 && tB < 1.0 - 1e-4) tSplitList.add(tB);
        }
      } else {
        final poly = punch.toPolygon();
        for (int i = 0; i < poly.length; i++) {
          final pa = poly[i];
          final pb = poly[(i + 1) % poly.length];
          final denom = (pb.y - pa.y) * dx - (pb.x - pa.x) * dy;
          if (denom.abs() > 1e-8) {
            final t = ((pb.x - pa.x) * (p1.y - pa.y) - (pb.y - pa.y) * (p1.x - pa.x)) / denom;
            final u = (dx * (p1.y - pa.y) - dy * (p1.x - pa.x)) / denom;
            if (t > 1e-4 && t < 1.0 - 1e-4 && u >= -1e-4 && u <= 1.0 + 1e-4) {
              tSplitList.add(t);
            }
          }
        }
      }
    }

    tSplitList.sort();
    final solidIntervals = <(double, double)>[];

    for (int i = 0; i < tSplitList.length - 1; i++) {
      final tA = tSplitList[i];
      final tB = tSplitList[i + 1];
      if ((tB - tA) * len < 0.2) continue;

      final tMid = (tA + tB) * 0.5;
      final pMid = CadPoint2D(p1.x + tMid * dx, p1.y + tMid * dy);

      // If pMid is inside ANY punch, it's a hole opening / notch!
      bool isInsideHole = false;
      for (final punch in punches) {
        if (_isPointInPunch(pMid, punch)) {
          isInsideHole = true;
          break;
        }
      }

      if (!isInsideHole) {
        solidIntervals.add((tA, tB));
      }
    }

    if (solidIntervals.isEmpty) {
      return [(0.0, 1.0)];
    }

    return solidIntervals;
  }

  /// Expands face boundary chord segments into smooth arc samples if they match doc.arcs.
  static List<CadPoint2D> _expandFaceWithArcs(List<CadPoint2D> vertices, List<CadArc2D> arcs, {double maxStepDeg = 8.0}) {
    if (vertices.length < 3 || arcs.isEmpty) return vertices;
    final n = vertices.length;
    final expanded = <CadPoint2D>[];

    int i = 0;
    while (i < n) {
      final current = vertices[i];
      CadArc2D? matchedArc;
      int targetIdx = -1;
      bool isReversed = false;

      for (final arc in arcs) {
        final isAtStart = current.distanceTo(arc.startPoint) < 2.0;
        final isAtEnd = current.distanceTo(arc.endPoint) < 2.0;

        if (isAtStart || isAtEnd) {
          final targetPoint = isAtStart ? arc.endPoint : arc.startPoint;
          final nextIdx = (i + 1) % n;
          if (vertices[nextIdx].distanceTo(targetPoint) < 2.0) {
            matchedArc = arc;
            targetIdx = nextIdx;
            isReversed = isAtEnd;
            break;
          }

          // Fallback for discretized polygons: check if an arc spans up to 16 chord vertices
          for (int k = 2; k <= math.min(16, n - 1); k++) {
            final checkIdx = (i + k) % n;
            if (vertices[checkIdx].distanceTo(targetPoint) < 2.0) {
              bool allOnArc = true;
              for (int m = 1; m < k; m++) {
                final midPt = vertices[(i + m) % n];
                if (arc.distanceTo(midPt) > 2.5) {
                  allOnArc = false;
                  break;
                }
              }
              if (allOnArc) {
                matchedArc = arc;
                targetIdx = checkIdx;
                isReversed = isAtEnd;
                break;
              }
            }
          }
          if (matchedArc != null) break;
        }
      }

      if (matchedArc != null && targetIdx != -1) {
        final samples = matchedArc.toPolygon(maxStepDeg: maxStepDeg);
        final orderedSamples = isReversed ? samples.reversed.toList() : samples;
        for (int s = 0; s < orderedSamples.length - 1; s++) {
          expanded.add(orderedSamples[s]);
        }
        if (targetIdx <= i) {
          // Wrapped around to start of loop
          break;
        }
        i = targetIdx;
      } else {
        expanded.add(current);
        i++;
      }
    }
    return expanded.length >= 3 ? expanded : vertices;
  }
}
