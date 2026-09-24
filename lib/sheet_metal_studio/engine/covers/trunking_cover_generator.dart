// =============================================================================
// trunking_cover_generator.dart
//
// Parametric Sheet Metal Cover Generator for Cable Trunking Accessories.
// Synthesizes 2D CAD flat patterns (outer contour, 90° bend lines, faces,
// mounting punch holes) for all standard trunking accessories:
// - 90° Bend & 45° Bend
// - Equal Tee & Unequal Tee (with Hbody - Hport extended 90° drop flaps)
// - Equal Cross & Unequal Cross (with Hbody - Hport extended 90° drop flaps)
// - 90° / 45° Inside & Outside Risers
// - Reducer
// =============================================================================

import 'dart:math' as math;
import '../../models/cad_primitives.dart';
import '../../models/dsf_document.dart';
import '../../models/fold_bend_line.dart';
import '../../models/planar_sheet_face.dart';
import '../../models/cnc_punch_primitive.dart';
import '../../models/trunking_cover_data.dart';
import '../../models/cms/cms_product_contract.dart';

class TrunkingCoverGenerator {
  /// Default flange depth (in mm) folding down over base vertical walls.
  static const double defaultFlangeDepth = 20.0;

  /// Default mounting hole diameter in mm at center of cover plate.
  static const double defaultMountHoleDiameter = 6.0;

  /// Default clearance (in mm) above base top rim when snapped in 3D to prevent base top flanges from piercing the cover.
  static const double defaultCoverClearanceZ = 3.0;

  /// Generates a complete, parametric [TrunkingCoverData] for [baseDocument].
  static TrunkingCoverData? generateCover(
    DsfDocument baseDocument, {
    Map<String, double>? parameterOverrides,
    double flangeDepth = defaultFlangeDepth,
    CoverPlacementMode2D placementMode2D = CoverPlacementMode2D.besideBase,
    CoverPlacementMode3D placementMode3D = CoverPlacementMode3D.snappedToBase,
    bool isVisible2D = true,
    bool isVisible3D = true,
    CadPoint2D? offset2D,
    CadPoint3D? offset3D,
  }) {
    final baseFloor = _findBaseFloor(baseDocument);
    if (baseFloor == null || baseFloor.vertices.length < 3) return null;

    final verts = baseFloor.vertices;
    final minX = verts.map((v) => v.x).reduce(math.min);
    final maxX = verts.map((v) => v.x).reduce(math.max);
    final minY = verts.map((v) => v.y).reduce(math.min);
    final maxY = verts.map((v) => v.y).reduce(math.max);
    final midX = (minX + maxX) / 2.0;
    final midY = (minY + maxY) / 2.0;

    // Determine product contract / profile
    final profile = _detectProfile(baseDocument);

    // Read port heights and body height
    final portHeights = _extractPortHeights(baseDocument, profile, parameterOverrides);
    final double bodyHeight;
    if (portHeights.isNotEmpty) {
      bodyHeight = portHeights.values.reduce(math.max);
    } else {
      bodyHeight = parameterOverrides?['height'] ?? (baseDocument.parameters['height'] as num?)?.toDouble() ?? 100.0;
    }

    final coverDoc = _buildCoverDocument(
      baseDocument: baseDocument,
      profile: profile,
      baseFloorVerts: verts,
      bodyHeight: bodyHeight,
      portHeights: portHeights,
      flangeDepth: flangeDepth,
      midX: midX,
      midY: midY,
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
    );

    // Compute automatic beside-base offset (placed cleanly to the right of the base part)
    final defaultOffset = computeDefaultBesideOffset(baseDocument, coverDoc);

    return TrunkingCoverData(
      document: coverDoc,
      isVisible2D: isVisible2D,
      isVisible3D: isVisible3D,
      placementMode2D: placementMode2D,
      placementMode3D: placementMode3D,
      offset2D: offset2D ?? (placementMode2D == CoverPlacementMode2D.snappedToBase
          ? const CadPoint2D(0, 0)
          : defaultOffset),
      offset3D: offset3D ?? const CadPoint3D(0, 0, 0),
      properties: {
        'productType': '${baseDocument.productType} Cover',
        'generatedBy': 'TruFold Studio Cover Engine',
        'flangeDepthMm': flangeDepth,
        'bodyHeightMm': bodyHeight,
        'snappedClearanceZ': defaultCoverClearanceZ,
      },
    );
  }

  /// Computes the default beside-base offset placing [coverDocument] cleanly to the right of [baseDocument].
  static CadPoint2D computeDefaultBesideOffset(DsfDocument baseDocument, DsfDocument coverDocument) {
    final baseBbox = calculateDocumentBbox(baseDocument);
    final coverBbox = calculateDocumentBbox(coverDocument);
    return CadPoint2D(
      (baseBbox.maxX - coverBbox.minX) + 60.0,
      baseBbox.minY - coverBbox.minY,
    );
  }

  /// Finds the primary floor face acting as base anchor in [doc].
  static PlanarSheetFace? _findBaseFloor(DsfDocument doc) {
    if (doc.faces.isEmpty) return null;
    return doc.faces.firstWhere(
      (f) => f.isBaseAnchor || f.role == FaceRole.baseFloor,
      orElse: () => doc.faces.first,
    );
  }

  /// Detects the fitting profile of [doc].
  static CmsScalingProfile _detectProfile(DsfDocument doc) {
    final contract = CmsProductContract.lookup(doc.productType, doc.itemName) ??
        CmsProductContract.lookup(null, doc.itemName) ??
        CmsProductContract.lookup(null, doc.productType);
    if (contract != null) return contract.scalingProfile;

    final type = '${doc.productType} ${doc.itemName}'.toLowerCase();
    if (type.contains('unequal') && type.contains('cross')) return CmsScalingProfile.unequalCross;
    if (type.contains('cross')) return CmsScalingProfile.equalCross;
    if (type.contains('unequal') && type.contains('tee')) return CmsScalingProfile.unequalTee;
    if (type.contains('tee')) return CmsScalingProfile.equalTee;
    if (type.contains('inside') && type.contains('riser')) return CmsScalingProfile.insideRiser;
    if (type.contains('outside') && type.contains('riser')) return CmsScalingProfile.outsideRiser;
    if (type.contains('45') && type.contains('bend')) return CmsScalingProfile.flatBend45;
    if (type.contains('90') && type.contains('bend')) return CmsScalingProfile.flatBend90;
    return CmsScalingProfile.generic;
  }

  /// Extracts port heights mapped by port index (1-based: 1, 2, 3, 4).
  static Map<int, double> _extractPortHeights(
    DsfDocument doc,
    CmsScalingProfile profile,
    Map<String, double>? overrides,
  ) {
    final heights = <int, double>{};
    for (int i = 1; i <= 4; i++) {
      final val = overrides?['port${i}_height'] ??
          overrides?['port${i}Height'] ??
          overrides?['port$i'] ??
          overrides?['p${i}_height'] ??
          overrides?['p${i}Height'] ??
          (doc.parameters['port${i}_height'] as num?)?.toDouble() ??
          (doc.parameters['port${i}Height'] as num?)?.toDouble() ??
          (doc.parameters['port$i'] as num?)?.toDouble() ??
          (doc.parameters['p${i}_height'] as num?)?.toDouble() ??
          (doc.parameters['p${i}Height'] as num?)?.toDouble();
      if (val != null && val > 0) {
        heights[i] = val;
      }
    }

    // CMS template / workflow ports
    final cmsRaw = doc.metadata['cmsTemplate'] ?? doc.metadata['cmsWorkflow'];
    if (cmsRaw is Map && cmsRaw['ports'] is List) {
      for (final p in cmsRaw['ports']) {
        if (p is Map) {
          final idx = (p['index'] as num?)?.toInt();
          final h = (p['height'] as num?)?.toDouble();
          if (idx != null && h != null && h > 0 && !heights.containsKey(idx)) {
            heights[idx] = h;
          }
        }
      }
    }

    // Baseline defaults for known unequal fittings
    if (profile == CmsScalingProfile.unequalTee) {
      // In standard Unequal Tee:
      // Port 1 (North/Branch): height 100mm
      // Port 2 (East/Right): height 50mm (smaller duct)
      // Port 3 (West/Left): height 100mm (main duct)
      double p1 = overrides?['port1_height'] ??
          overrides?['port1Height'] ??
          (doc.parameters['port1_height'] as num?)?.toDouble() ??
          (doc.parameters['port1Height'] as num?)?.toDouble() ??
          100.0;

      double p2 = overrides?['port2_height'] ??
          overrides?['port2Height'] ??
          (doc.parameters['port2_height'] as num?)?.toDouble() ??
          (doc.parameters['port2Height'] as num?)?.toDouble() ??
          50.0;

      double p3 = overrides?['port3_height'] ??
          overrides?['port3Height'] ??
          (doc.parameters['port3_height'] as num?)?.toDouble() ??
          (doc.parameters['port3Height'] as num?)?.toDouble() ??
          100.0;

      // In Unequal Tee, Port 3 is the main 100mm through duct and Port 2 is the 50mm step-down duct.
      // If template parameters inadvertently swapped them (port2=100, port3=50), align with physical CAD geometry:
      if (overrides == null && p2 > p3 && (p3 - 50.0).abs() < 1e-3) {
        final tmp = p2;
        p2 = p3;
        p3 = tmp;
      }

      heights[1] = p1;
      heights[2] = p2;
      heights[3] = p3;
    } else if (profile == CmsScalingProfile.unequalCross) {
      // In standard Unequal Cross:
      // Ports 1 & 3: height 50mm
      // Ports 2 & 4: height 100mm
      final p1H = overrides?['port1_height'] ??
          overrides?['port1Height'] ??
          (doc.parameters['port1_height'] as num?)?.toDouble() ??
          (doc.parameters['port1Height'] as num?)?.toDouble();
      heights[1] = p1H ?? 50.0;

      final p2H = overrides?['port2_height'] ??
          overrides?['port2Height'] ??
          (doc.parameters['port2_height'] as num?)?.toDouble() ??
          (doc.parameters['port2Height'] as num?)?.toDouble();
      heights[2] = p2H ?? 100.0;

      final p3H = overrides?['port3_height'] ??
          overrides?['port3Height'] ??
          (doc.parameters['port3_height'] as num?)?.toDouble() ??
          (doc.parameters['port3Height'] as num?)?.toDouble();
      heights[3] = p3H ?? 50.0;

      final p4H = overrides?['port4_height'] ??
          overrides?['port4Height'] ??
          (doc.parameters['port4_height'] as num?)?.toDouble() ??
          (doc.parameters['port4Height'] as num?)?.toDouble();
      heights[4] = p4H ?? 100.0;
    }

    if (heights.isEmpty) {
      final h = overrides?['height'] ?? (doc.parameters['height'] as num?)?.toDouble();
      if (h != null) {
        heights[1] = h;
        heights[2] = h;
        heights[3] = h;
      }
    }
    return heights;
  }

  /// Core parametric builder assembling the 2D cover document.
  static DsfDocument _buildCoverDocument({
    required DsfDocument baseDocument,
    required CmsScalingProfile profile,
    required List<CadPoint2D> baseFloorVerts,
    required double bodyHeight,
    required Map<int, double> portHeights,
    required double flangeDepth,
    required double midX,
    required double midY,
    required double minX,
    required double maxX,
    required double minY,
    required double maxY,
  }) {
    // Detect orientation (CCW vs CW)
    double signedArea = 0.0;
    final n = baseFloorVerts.length;
    for (int i = 0; i < n; i++) {
      final v1 = baseFloorVerts[i];
      final v2 = baseFloorVerts[(i + 1) % n];
      signedArea += (v1.x * v2.y - v2.x * v1.y);
    }
    final isCcw = signedArea > 0.0;

    final outerContour = <CadPoint2D>[];
    final bends = <FoldBendLine>[];
    final faces = <PlanarSheetFace>[];
    int flangeCounter = 1;
    int dropFlapCounter = 1;

    // Main top face vertices (matching the base floor footprint)
    final mainFaceVerts = List<CadPoint2D>.from(baseFloorVerts);

    // Iterate through every edge of the base floor
    for (int i = 0; i < n; i++) {
      final p1 = baseFloorVerts[i];
      final p2 = baseFloorVerts[(i + 1) % n];
      final dx = p2.x - p1.x;
      final dy = p2.y - p1.y;
      final edgeLen = math.sqrt(dx * dx + dy * dy);
      if (edgeLen < 1e-3) continue;

      // Calculate unit outward normal vector
      final double nx, ny;
      if (isCcw) {
        nx = dy / edgeLen;
        ny = -dx / edgeLen;
      } else {
        nx = -dy / edgeLen;
        ny = dx / edgeLen;
      }

      // Check if this edge is a port mouth opening or a wall/cheek edge
      final portIndex = _identifyPortIndex(p1, p2, midX, midY, profile);
      final isPortMouth = portIndex != null;

      if (!isPortMouth) {
        // --- Wall / Cheek Edge: Bends down 90° with a side flange ---
        final bendId = 'CB_$flangeCounter';
        final flangeFaceId = 'CF_$flangeCounter';

        bends.add(FoldBendLine(
          id: bendId,
          p1: p1,
          p2: p2,
          targetAngleDeg: 90.0,
          direction: BendDirection.down,
          radiusMm: 1.5,
          layer: 'BEND_DOWN',
          parentFaceId: 'COVER_MAIN_FACE',
          childFaceId: flangeFaceId,
        ));

        // Flange outer vertices extending along outward normal
        final f1 = CadPoint2D(p1.x + nx * flangeDepth, p1.y + ny * flangeDepth);
        final f2 = CadPoint2D(p2.x + nx * flangeDepth, p2.y + ny * flangeDepth);

        faces.add(PlanarSheetFace(
          id: flangeFaceId,
          label: 'Cover Side Flange $flangeCounter',
          role: FaceRole.returnFlange,
          vertices: [p1, p2, f2, f1],
        ));

        outerContour.addAll([p1, f1, f2, p2]);
        flangeCounter++;
      } else {
        // --- Port Mouth Edge: Check for negative/void area that must be covered ---
        final portH = portHeights[portIndex] ?? bodyHeight;
        final dropFlapLength = bodyHeight - portH;

        if (dropFlapLength > 0.5) {
          // Additional 90° downward flap covering the port void down to the lower port walls
          final bendId = 'C_DROP_B_$dropFlapCounter';
          final flapFaceId = 'C_DROP_F_$dropFlapCounter';

          bends.add(FoldBendLine(
            id: bendId,
            p1: p1,
            p2: p2,
            targetAngleDeg: 90.0,
            direction: BendDirection.down,
            radiusMm: 1.5,
            layer: 'BEND_DOWN',
            parentFaceId: 'COVER_MAIN_FACE',
            childFaceId: flapFaceId,
          ));

          final d1 = CadPoint2D(p1.x + nx * dropFlapLength, p1.y + ny * dropFlapLength);
          final d2 = CadPoint2D(p2.x + nx * dropFlapLength, p2.y + ny * dropFlapLength);

          faces.add(PlanarSheetFace(
            id: flapFaceId,
            label: 'Port $portIndex Flap (${dropFlapLength.toStringAsFixed(1)}mm)',
            role: FaceRole.returnFlange,
            vertices: [p1, p2, d2, d1],
          ));

          outerContour.addAll([p1, d1, d2, p2]);
          dropFlapCounter++;
        } else {
          // Port height == body height: open mouth (no flap)
          outerContour.addAll([p1, p2]);
        }
      }
    }

    // Add main face
    faces.insert(0, PlanarSheetFace(
      id: 'COVER_MAIN_FACE',
      label: 'Cover Top Plate',
      role: FaceRole.baseFloor,
      isBaseAnchor: true,
      vertices: mainFaceVerts,
    ));

    // Fastener / mounting hole punch at center
    final punches = [
      CncPunchPrimitive(
        id: 'COVER_MOUNT_HOLE',
        type: PunchType.roundHole,
        center: CadPoint2D(midX, midY),
        diameterMm: defaultMountHoleDiameter,
        rotationDeg: 0.0,
        role: CncPunchRole.general,
        parentFaceId: 'COVER_MAIN_FACE',
        showLabel: true,
        isVisible: true,
      ),
    ];

    // Deduplicate adjacent vertices in outerContour
    final cleanContour = _sanitizeContour(outerContour);

    return DsfDocument(
      productType: '${baseDocument.productType} Cover',
      itemName: '${baseDocument.itemName} Cover',
      material: baseDocument.material,
      outerContour: cleanContour.isNotEmpty ? cleanContour : mainFaceVerts,
      bends: bends,
      faces: faces,
      punches: punches,
      baseFaceId: 'COVER_MAIN_FACE',
      parameters: {
        ...baseDocument.parameters,
        'cover_flange_depth': flangeDepth,
        'cover_body_height': bodyHeight,
      },
      metadata: {
        'isCover': true,
        'parentProductType': baseDocument.productType,
        'parentItemName': baseDocument.itemName,
        'generator': 'TruFold Studio Cover Engine',
      },
    );
  }

  /// Identifies whether the edge from [p1] to [p2] corresponds to a port mouth opening.
  /// Returns 1-based port index (1, 2, 3, 4) or null if it's a wall/cheek edge.
  static int? _identifyPortIndex(
    CadPoint2D p1,
    CadPoint2D p2,
    double midX,
    double midY,
    CmsScalingProfile profile,
  ) {
    final dx = (p2.x - p1.x).abs();
    final dy = (p2.y - p1.y).abs();
    final edgeMidX = (p1.x + p2.x) / 2.0;
    final edgeMidY = (p1.y + p2.y) / 2.0;

    // Diagonal edges (dx > 5 && dy > 5) in Cross and Tee are 45° corner cheeks!
    final isDiagonal = dx > 5.0 && dy > 5.0;
    if (isDiagonal) return null;

    if (profile == CmsScalingProfile.equalCross || profile == CmsScalingProfile.unequalCross) {
      // 4 orthogonal mouth edges in Cross:
      // North: Port 1
      if (edgeMidY < midY - 20.0 && dy < 5.0) return 1;
      // East: Port 2
      if (edgeMidX > midX + 20.0 && dx < 5.0) return 2;
      // West: Port 3
      if (edgeMidX < midX - 20.0 && dx < 5.0) return 3;
      // South: Port 4
      if (edgeMidY > midY + 20.0 && dy < 5.0) return 4;
      return null;
    }

    if (profile == CmsScalingProfile.equalTee || profile == CmsScalingProfile.unequalTee) {
      // Top mouth: Port 1 (North)
      if (edgeMidY < midY - 20.0 && dy < 5.0) return 1;
      // Right mouth: Port 2 (East)
      if (edgeMidX > midX + 20.0 && dx < 5.0) return 2;
      // Left mouth: Port 3 (West)
      if (edgeMidX < midX - 20.0 && dx < 5.0) return 3;
      // Bottom horizontal edge: bottom wall (NOT a port!)
      return null;
    }

    if (profile == CmsScalingProfile.flatBend90 || profile == CmsScalingProfile.flatBend45) {
      // In Bends, the two open mouth ends are ports 1 and 2
      if (edgeMidY < midY - 15.0) return 1;
      return 2;
    }

    return null;
  }

  /// Removes duplicate consecutive points from [contour].
  static List<CadPoint2D> _sanitizeContour(List<CadPoint2D> contour) {
    if (contour.isEmpty) return const [];
    final result = <CadPoint2D>[contour.first];
    for (int i = 1; i < contour.length; i++) {
      if (contour[i].distanceTo(result.last) > 0.05) {
        result.add(contour[i]);
      }
    }
    if (result.length > 2 && result.first.distanceTo(result.last) < 0.05) {
      result.removeLast();
    }
    return result;
  }

  /// Calculates the 2D bounding box of all geometric entities in [doc].
  static ({double minX, double maxX, double minY, double maxY}) calculateDocumentBbox(DsfDocument doc) {
    double minX = 0, maxX = 0, minY = 0, maxY = 0;
    bool hasBounds = false;

    void update(double x, double y) {
      if (!hasBounds) {
        minX = maxX = x;
        minY = maxY = y;
        hasBounds = true;
      } else {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }

    for (final p in doc.outerContour) {
      update(p.x, p.y);
    }
    for (final b in doc.bends) {
      update(b.p1.x, b.p1.y);
      update(b.p2.x, b.p2.y);
    }
    for (final f in doc.faces) {
      for (final v in f.vertices) {
        update(v.x, v.y);
      }
    }

    if (!hasBounds) {
      return (minX: 0.0, maxX: 100.0, minY: 0.0, maxY: 100.0);
    }
    return (minX: minX, maxX: maxX, minY: minY, maxY: maxY);
  }
}
