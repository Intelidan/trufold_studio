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
import '../cms/cms_scaling_controller.dart';

class TrunkingCoverGenerator {
  /// Default flange depth (in mm) folding down over base vertical walls.
  static const double defaultFlangeDepth = 12.0;

  /// Default mounting hole diameter in mm at center of cover plate.
  static const double defaultMountHoleDiameter = 6.0;

  /// Default clearance (in mm) above base top rim when snapped in 3D to float 2 to 3mm above flange top face.
  static const double defaultCoverClearanceZ = 5.0;

  /// Default outward clearance (in mm) expanding the cover plate beyond the base floor
  /// so down-folded cover flanges fit snugly over the main body's outer perimeter without touching flanges.
  static const double defaultCoverClearanceOffset = 2.0;

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

    // Determine product contract / profile
    final profile = _detectProfile(baseDocument);
    final portHeights = _extractPortHeights(baseDocument, profile, parameterOverrides);

    List<CadPoint2D> coverFootprintVerts = verts;
    double effectiveMinX = minX;
    double effectiveMaxX = maxX;
    double effectiveMinY = minY;
    double effectiveMaxY = maxY;

    double slantedCoverLength = 0.0;
    double reducerSlopeAngleRad = 0.0;
    double reducerPort1Y = 0.0;
    double reducerPort1Height = 0.0;
    double reducerPort2Height = 0.0;

    if (profile == CmsScalingProfile.reducer || CmsScalingController.isReducerGeometry(baseDocument)) {
      final cheekBends = baseDocument.bends
          .where((b) => (b.targetAngleDeg.abs() - 90.0).abs() < 15.0 && b.role != BendLineRole.flange && !b.id.toUpperCase().startsWith('FL'))
          .toList()
        ..sort((a, b) => ((a.p1.x + a.p2.x) / 2.0).compareTo((b.p1.x + b.p2.x) / 2.0));
      final b1 = cheekBends.isNotEmpty ? cheekBends.first : null;
      final b2 = cheekBends.isNotEmpty ? cheekBends.last : null;

      final double y1 = b1 != null ? math.min(b1.p1.y, b1.p2.y) : minY;
      final double y2 = b1 != null ? math.max(b1.p1.y, b1.p2.y) : maxY;

      double p1X1 = minX, p1X2 = maxX;
      double p2X1 = minX, p2X2 = maxX;

      if (b1 != null && b2 != null) {
        p1X1 = b1.p1.y < b1.p2.y ? b1.p1.x : b1.p2.x;
        p2X1 = b1.p1.y > b1.p2.y ? b1.p1.x : b1.p2.x;
        p1X2 = b2.p1.y < b2.p2.y ? b2.p1.x : b2.p2.x;
        p2X2 = b2.p1.y > b2.p2.y ? b2.p1.x : b2.p2.x;
      }

      final h1 = portHeights[1] ?? 100.0;
      final h2 = portHeights[2] ?? 50.0;
      final deltaH = h1 - h2;
      final lengthL = (y2 - y1).abs();
      slantedCoverLength = math.sqrt(lengthL * lengthL + deltaH * deltaH);
      reducerSlopeAngleRad = lengthL > 1e-4 ? math.atan2(deltaH, lengthL) : 0.0;
      reducerPort1Y = y1;
      reducerPort1Height = h1;
      reducerPort2Height = h2;

      final cOffset = defaultCoverClearanceOffset;
      coverFootprintVerts = [
        CadPoint2D(p1X1 - cOffset, y1),
        CadPoint2D(p1X2 + cOffset, y1),
        CadPoint2D(p2X2 + cOffset, y1 + slantedCoverLength),
        CadPoint2D(p2X1 - cOffset, y1 + slantedCoverLength),
      ];

      effectiveMinX = math.min(p1X1, p2X1) - cOffset;
      effectiveMaxX = math.max(p1X2, p2X2) + cOffset;
      effectiveMinY = y1;
      effectiveMaxY = y1 + slantedCoverLength;
    } else if (profile == CmsScalingProfile.insideRiser) {
      final bends45 = baseDocument.bends.where((b) => (b.targetAngleDeg.abs() - 45.0).abs() < 15.0).toList();
      final is90InsideRiser = bends45.length >= 2;

      if (is90InsideRiser) {
        // 90° Inside Riser:
        // Top opening sits between Cheek 1 (B1) and Cheek 2 (B2) in X,
        // and covers the return flanges FL1 and FL2 in Y.
        // Official manufacturer specification (90_deg_inside_riser_100x100_cover.dxf):
        // Cover plate length is 55.0mm, centered on the return flanges (yMid ~ 113.84mm).
        // This extends ~0.68mm beyond the flanges at both ends, touching the cheek knee bend
        // line without hanging over the flat face on the right hand side into empty space.
        final cheekBends = baseDocument.bends
            .where((b) => (b.targetAngleDeg.abs() - 90.0).abs() < 15.0 && b.role != BendLineRole.flange && !b.id.toUpperCase().startsWith('FL'))
            .toList()
          ..sort((a, b) => ((a.p1.x + a.p2.x) / 2.0).compareTo((b.p1.x + b.p2.x) / 2.0));
        final double cheekX1 = cheekBends.isNotEmpty ? math.min(cheekBends.first.p1.x, cheekBends.first.p2.x) : minX;
        final double cheekX2 = cheekBends.isNotEmpty ? math.max(cheekBends.last.p1.x, cheekBends.last.p2.x) : maxX;

        final returnFlanges = baseDocument.bends.where((b) =>
          b.role == BendLineRole.flange || b.layer == 'FLANGE' || b.id.toUpperCase().startsWith('FL')
        ).toList();
        double flangeMinY = minY;
        double flangeMaxY = maxY;
        if (returnFlanges.isNotEmpty) {
          flangeMinY = returnFlanges.map((b) => math.min(b.p1.y, b.p2.y)).reduce(math.min);
          flangeMaxY = returnFlanges.map((b) => math.max(b.p1.y, b.p2.y)).reduce(math.max);
        }
        final flangeLen = flangeMaxY - flangeMinY; // ~53.64mm
        final yMid = (flangeMinY + flangeMaxY) / 2.0; // ~113.84mm
        final coverLen = math.max(55.0, flangeLen + 1.36);

        effectiveMinX = cheekX1;
        effectiveMaxX = cheekX2;
        effectiveMinY = yMid - coverLen / 2.0;
        effectiveMaxY = yMid + coverLen / 2.0;

        coverFootprintVerts = [
          CadPoint2D(effectiveMinX, effectiveMinY),
          CadPoint2D(effectiveMaxX, effectiveMinY),
          CadPoint2D(effectiveMaxX, effectiveMaxY),
          CadPoint2D(effectiveMinX, effectiveMaxY),
        ];
      } else {
        // SS2: For 45 deg inside riser, reduce length of cover so it does not extend
        // beyond the top horizontal flat opening. The prongs inclined 45 deg upwards
        // are coupler flaps for linking adjacent trunking and must remain unobstructed.
        double? horizEnd;
        final returnFlanges = baseDocument.bends.where((b) =>
          b.role == BendLineRole.flange || b.layer == 'FLANGE' || b.id.toUpperCase().startsWith('FL')
        ).toList();
        if (returnFlanges.isNotEmpty) {
          final maxFlangeY = returnFlanges.map((b) => math.max(b.p1.y, b.p2.y)).reduce(math.max);
          if (maxFlangeY > minY + 10.0 && maxFlangeY < maxY) {
            horizEnd = maxFlangeY;
          }
        }
        horizEnd ??= minY + (maxY - minY) * 0.564;
        effectiveMaxY = horizEnd;
        coverFootprintVerts = [
          CadPoint2D(minX, minY),
          CadPoint2D(maxX, minY),
          CadPoint2D(maxX, effectiveMaxY),
          CadPoint2D(minX, effectiveMaxY),
        ];
      }
    } else if (profile == CmsScalingProfile.outsideRiser) {
      final cheekBends = baseDocument.bends
          .where((b) => (b.targetAngleDeg.abs() - 90.0).abs() < 15.0 && b.role != BendLineRole.flange && !b.id.toUpperCase().startsWith('FL'))
          .toList();
      final isHorizontal = cheekBends.isNotEmpty &&
          (cheekBends.first.p2.x - cheekBends.first.p1.x).abs() > (cheekBends.first.p2.y - cheekBends.first.p1.y).abs();

      if (isHorizontal) {
        // 90° Outside Riser: cover flanged area between FL1 and FL2 along X,
        // and between Cheek 1 (B1) and Cheek 2 (B2) along Y.
        final returnFlanges = baseDocument.bends.where((b) =>
          b.role == BendLineRole.flange || b.layer == 'FLANGE' || b.id.toUpperCase().startsWith('FL')
        ).toList();
        double flangeMinX = minX;
        double flangeMaxX = maxX;
        if (returnFlanges.isNotEmpty) {
          flangeMinX = returnFlanges.map((b) => math.min(b.p1.x, b.p2.x)).reduce(math.min);
          flangeMaxX = returnFlanges.map((b) => math.max(b.p1.x, b.p2.x)).reduce(math.max);
        }
        final cheekY1 = cheekBends.map((b) => (b.p1.y + b.p2.y) / 2.0).reduce(math.min);
        final cheekY2 = cheekBends.map((b) => (b.p1.y + b.p2.y) / 2.0).reduce(math.max);

        effectiveMinX = flangeMinX;
        effectiveMaxX = flangeMaxX;
        effectiveMinY = cheekY1;
        effectiveMaxY = cheekY2;

        coverFootprintVerts = [
          CadPoint2D(effectiveMinX, effectiveMinY),
          CadPoint2D(effectiveMaxX, effectiveMinY),
          CadPoint2D(effectiveMaxX, effectiveMaxY),
          CadPoint2D(effectiveMinX, effectiveMaxY),
        ];
      } else {
        // SS3: For 45 deg outside riser, cover the whole straight top opening
        // extending all the way to the knee where the top rim bends down 45 degrees
        // (the end marked with the red circle, at Y ~ 133.4mm / length ~ 103.4mm).
        double straightEnd = maxY;
        final returnFlanges = baseDocument.bends.where((b) =>
          b.role == BendLineRole.flange || b.layer == 'FLANGE' || b.id.toUpperCase().startsWith('FL')
        ).toList();
        if (returnFlanges.isNotEmpty) {
          final maxFlangeY = returnFlanges.map((b) => math.max(b.p1.y, b.p2.y)).reduce(math.max);
          if (maxFlangeY > straightEnd) {
            straightEnd = maxFlangeY;
          }
        }

        // Check sidewall top rim: the straight horizontal opening extends past the return flange
        // (which has a 10mm corner relief) all the way to the 45° knee where the top rim angles down.
        final sidewalls = baseDocument.faces.where((f) => f.role == FaceRole.sideWall).toList();
        for (final wall in sidewalls) {
          for (final fl in returnFlanges) {
            final flangeX = (fl.p1.x + fl.p2.x) / 2.0;
            for (final v in wall.vertices) {
              if ((v.x - flangeX).abs() < 1.0 && v.y > straightEnd) {
                straightEnd = v.y;
              }
            }
          }
        }

        effectiveMaxY = straightEnd;
        coverFootprintVerts = [
          CadPoint2D(minX, minY),
          CadPoint2D(maxX, minY),
          CadPoint2D(maxX, effectiveMaxY),
          CadPoint2D(minX, effectiveMaxY),
        ];
      }
    }

    final midX = (effectiveMinX + effectiveMaxX) / 2.0;
    final midY = (effectiveMinY + effectiveMaxY) / 2.0;

    // Read body height
    double? detectedH = parameterOverrides?['height'];
    if (detectedH == null || detectedH <= 0) {
      if (portHeights.isNotEmpty) {
        detectedH = portHeights.values.reduce(math.max);
      }
    }
    detectedH ??= (baseDocument.parameters['height'] as num?)?.toDouble();
    if (detectedH == null || detectedH <= 0) {
      // Try regex from itemName or productType, e.g. 100x50 or 45x100
      final m = RegExp(r'(\d+)\s*[xX]\s*(\d+)').firstMatch('${baseDocument.itemName} ${baseDocument.productType}');
      if (m != null) {
        final d1 = double.tryParse(m.group(1)!);
        final d2 = double.tryParse(m.group(2)!);
        if (d1 != null && d2 != null) {
          detectedH = math.min(d1, d2);
        }
      }
    }
    if (detectedH == null || detectedH <= 0) {
      for (final b in baseDocument.bends) {
        if (b.role != BendLineRole.flange && (b.targetAngleDeg.abs() - 90.0).abs() < 15.0) {
          final sideFace = baseDocument.faces.where((f) => f.id == b.childFaceId || f.id == b.parentFaceId).firstOrNull;
          if (sideFace != null && sideFace.id != baseFloor.id) {
            final h = _estimateFaceHeight(sideFace.vertices);
            if (h > 15.0) {
              detectedH = math.max(detectedH ?? 0.0, h);
            }
          }
        }
      }
    }
    final double bodyHeight = detectedH ?? 100.0;

    final DsfDocument coverDoc;
    if (profile == CmsScalingProfile.outsideRiser) {
      coverDoc = _buildOutsideRiserCoverDocument(
        baseDocument: baseDocument,
        bodyHeight: bodyHeight,
        flangeDepth: flangeDepth,
        parameterOverrides: parameterOverrides,
      );
    } else {
      coverDoc = _buildCoverDocument(
        baseDocument: baseDocument,
        profile: profile,
        baseFloorVerts: coverFootprintVerts,
        bodyHeight: bodyHeight,
        portHeights: portHeights,
        flangeDepth: flangeDepth,
        midX: midX,
        midY: midY,
        minX: effectiveMinX,
        maxX: effectiveMaxX,
        minY: effectiveMinY,
        maxY: effectiveMaxY,
      );
    }

    // Compute automatic beside-base offset (placed cleanly to the right of the base part)
    final defaultOffset = computeDefaultBesideOffset(baseDocument, coverDoc);

      final isTray = baseDocument.productType.toLowerCase().contains('tray') ||
          baseDocument.itemName.toLowerCase().contains('tray') ||
          baseDocument.bends.any((b) => b.role == BendLineRole.flange && (b.targetAngleDeg.abs() - 135.0).abs() < 10.0);

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
          'snappedClearanceZ': isTray ? 0.5 : defaultCoverClearanceZ,
          'snugFitClearanceMm': defaultCoverClearanceOffset,
        if (profile == CmsScalingProfile.reducer || CmsScalingController.isReducerGeometry(baseDocument)) ...{
          'isReducerCover': true,
          'port1Height': reducerPort1Height,
          'port2Height': reducerPort2Height,
          'port1Y': reducerPort1Y,
          'port2Y': effectiveMaxY,
          'lengthL': (effectiveMaxY - reducerPort1Y).abs(),
          'slantedLength': slantedCoverLength,
          'slopeAngleRad': reducerSlopeAngleRad,
        },
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
    if (type.contains('reducer') || CmsScalingController.isReducerGeometry(doc)) return CmsScalingProfile.reducer;
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
    if (profile == CmsScalingProfile.reducer || CmsScalingController.isReducerGeometry(doc)) {
      final p1H = overrides?['port1_height'] ??
          overrides?['port1Height'] ??
          overrides?['port1'] ??
          overrides?['p1_height'] ??
          overrides?['p1Height'] ??
          (doc.parameters['port1_height'] as num?)?.toDouble() ??
          (doc.parameters['port1Height'] as num?)?.toDouble() ??
          (doc.parameters['height'] as num?)?.toDouble() ??
          heights[1] ??
          100.0;
      final p2H = overrides?['port2_height'] ??
          overrides?['port2Height'] ??
          overrides?['port2'] ??
          overrides?['p2_height'] ??
          overrides?['p2Height'] ??
          (doc.parameters['port2_height'] as num?)?.toDouble() ??
          (doc.parameters['port2Height'] as num?)?.toDouble() ??
          heights[2] ??
          50.0;
      heights[1] = p1H;
      heights[2] = p2H;
    } else if (profile == CmsScalingProfile.unequalTee) {
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
      // Ports 1 & 3: height 50mm (West and East branches)
      // Ports 2 & 4: height 100mm (North and South main run)
      final p1H = overrides?['port1_height'] ??
          overrides?['port1Height'] ??
          overrides?['port1'] ??
          overrides?['p1_height'] ??
          overrides?['p1Height'] ??
          (doc.parameters['port1_height'] as num?)?.toDouble() ??
          (doc.parameters['port1Height'] as num?)?.toDouble() ??
          (doc.parameters['port1'] as num?)?.toDouble() ??
          heights[1];
      heights[1] = p1H ?? 50.0;

      final p2H = overrides?['port2_height'] ??
          overrides?['port2Height'] ??
          overrides?['port2'] ??
          overrides?['p2_height'] ??
          overrides?['p2Height'] ??
          (doc.parameters['port2_height'] as num?)?.toDouble() ??
          (doc.parameters['port2Height'] as num?)?.toDouble() ??
          (doc.parameters['port2'] as num?)?.toDouble() ??
          heights[2];
      heights[2] = p2H ?? 100.0;

      final p3H = overrides?['port3_height'] ??
          overrides?['port3Height'] ??
          overrides?['port3'] ??
          overrides?['p3_height'] ??
          overrides?['p3Height'] ??
          (doc.parameters['port3_height'] as num?)?.toDouble() ??
          (doc.parameters['port3Height'] as num?)?.toDouble() ??
          (doc.parameters['port3'] as num?)?.toDouble() ??
          heights[3];
      heights[3] = p3H ?? 50.0;

      final p4H = overrides?['port4_height'] ??
          overrides?['port4Height'] ??
          overrides?['port4'] ??
          overrides?['p4_height'] ??
          overrides?['p4Height'] ??
          (doc.parameters['port4_height'] as num?)?.toDouble() ??
          (doc.parameters['port4Height'] as num?)?.toDouble() ??
          (doc.parameters['port4'] as num?)?.toDouble() ??
          heights[4];
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

  /// Dedicated parametric builder for Outside Riser covers (both 90° and 45°):
  /// - 90° Outside Riser (horizontal cheek bends along X):
  ///   - Top flat roof panel spans between cheek knee points along X (e.g. ~143mm).
  ///   - Both ends extend along X with 45° downward roof bends, sloping towards the coupler flaps.
  ///   - 90° downward side flanges along Y at yMin and yMax with 90° V-notches at each 45° roof bend line.
  ///   - Central fastener mounting hole.
  /// - 45° Outside Riser (vertical cheek bends along Y):
  ///   - Straight opening at yStart (~30mm) is open without flanges.
  ///   - Flat roof spans from yStart to yKnee (~133.4mm).
  ///   - One end (yKnee) extends with a 45° downward roof bend, sloping towards the coupler flap.
  ///   - 90° downward side flanges along X at xMin and xMax with a 90° V-notch at the 45° roof bend line.
  ///   - Central fastener mounting hole.
  static DsfDocument _buildOutsideRiserCoverDocument({
    required DsfDocument baseDocument,
    required double bodyHeight,
    required double flangeDepth,
    Map<String, double>? parameterOverrides,
  }) {
    final cheekBends = baseDocument.bends
        .where((b) => (b.targetAngleDeg.abs() - 90.0).abs() < 15.0 && b.role != BendLineRole.flange && !b.id.toUpperCase().startsWith('FL'))
        .toList();
    final isHorizontal = cheekBends.isNotEmpty &&
        (cheekBends.first.p2.x - cheekBends.first.p1.x).abs() > (cheekBends.first.p2.y - cheekBends.first.p1.y).abs();

    const clearance = defaultCoverClearanceOffset;
    final d = flangeDepth;

    if (isHorizontal) {
      // -------------------------------------------------------------
      // 90° Outside Riser (horizontal cheek bends along X)
      // -------------------------------------------------------------
      // 1. Channel width in Y:
      cheekBends.sort((a, b) => ((a.p1.y + a.p2.y) / 2.0).compareTo((b.p1.y + b.p2.y) / 2.0));
      final b1 = cheekBends.first;
      final b2 = cheekBends.last;
      final y1 = math.min((b1.p1.y + b1.p2.y) / 2.0, (b2.p1.y + b2.p2.y) / 2.0);
      final y2 = math.max((b1.p1.y + b1.p2.y) / 2.0, (b2.p1.y + b2.p2.y) / 2.0);
      final yMin = y1 - clearance;
      final yMax = y2 + clearance;

      // 2. Flat top opening span in X:
      final returnFlanges = baseDocument.bends.where((b) =>
        b.role == BendLineRole.flange || b.layer == 'FLANGE' || b.id.toUpperCase().startsWith('FL')
      ).toList();
      double x1 = 42.3;
      double x2 = 185.5;
      if (returnFlanges.isNotEmpty) {
        final flMinX = returnFlanges.map((b) => math.min(b.p1.x, b.p2.x)).reduce(math.min);
        final flMaxX = returnFlanges.map((b) => math.max(b.p1.x, b.p2.x)).reduce(math.max);
        x1 = flMinX - 10.0;
        x2 = flMaxX + 10.0;
      }

      // 3. Extension length at each 45° angled end:
      final baseH = (baseDocument.parameters['height'] as num?)?.toDouble() ?? 100.0;
      final deltaH = bodyHeight - baseH;
      final lExt = math.max(20.0, 40.0 + deltaH * 0.5);
      final xStart = x1 - lExt;
      final xEnd = x2 + lExt;

      // 4. Faces:
      final mainFace = PlanarSheetFace(
        id: 'COVER_MAIN_FACE',
        label: 'Cover Top Plate',
        role: FaceRole.baseFloor,
        isBaseAnchor: true,
        vertices: [CadPoint2D(x1, yMin), CadPoint2D(x2, yMin), CadPoint2D(x2, yMax), CadPoint2D(x1, yMax)],
      );

      final ext1Face = PlanarSheetFace(
        id: 'COVER_EXT_FACE_1',
        label: 'Cover Port 1 Angled Extension (45°)',
        role: FaceRole.returnFlange,
        vertices: [CadPoint2D(xStart, yMin), CadPoint2D(x1, yMin), CadPoint2D(x1, yMax), CadPoint2D(xStart, yMax)],
      );

      final ext2Face = PlanarSheetFace(
        id: 'COVER_EXT_FACE_2',
        label: 'Cover Port 2 Angled Extension (45°)',
        role: FaceRole.returnFlange,
        vertices: [CadPoint2D(x2, yMin), CadPoint2D(xEnd, yMin), CadPoint2D(xEnd, yMax), CadPoint2D(x2, yMax)],
      );

      final cfMainBot = PlanarSheetFace(
        id: 'CF_MAIN_BOT',
        label: 'Cover Center Bottom Flange',
        role: FaceRole.returnFlange,
        vertices: [CadPoint2D(x1, yMin), CadPoint2D(x1 + d, yMin - d), CadPoint2D(x2 - d, yMin - d), CadPoint2D(x2, yMin)],
      );
      final cfMainTop = PlanarSheetFace(
        id: 'CF_MAIN_TOP',
        label: 'Cover Center Top Flange',
        role: FaceRole.returnFlange,
        vertices: [CadPoint2D(x1, yMax), CadPoint2D(x2, yMax), CadPoint2D(x2 - d, yMax + d), CadPoint2D(x1 + d, yMax + d)],
      );

      final cfExt1Bot = PlanarSheetFace(
        id: 'CF_EXT1_BOT',
        label: 'Cover Ext 1 Bottom Flange',
        role: FaceRole.returnFlange,
        vertices: [CadPoint2D(xStart, yMin), CadPoint2D(xStart, yMin - d), CadPoint2D(x1 - d, yMin - d), CadPoint2D(x1, yMin)],
      );
      final cfExt1Top = PlanarSheetFace(
        id: 'CF_EXT1_TOP',
        label: 'Cover Ext 1 Top Flange',
        role: FaceRole.returnFlange,
        vertices: [CadPoint2D(xStart, yMax), CadPoint2D(x1, yMax), CadPoint2D(x1 - d, yMax + d), CadPoint2D(xStart, yMax + d)],
      );

      final cfExt2Bot = PlanarSheetFace(
        id: 'CF_EXT2_BOT',
        label: 'Cover Ext 2 Bottom Flange',
        role: FaceRole.returnFlange,
        vertices: [CadPoint2D(x2, yMin), CadPoint2D(x2 + d, yMin - d), CadPoint2D(xEnd, yMin - d), CadPoint2D(xEnd, yMin)],
      );
      final cfExt2Top = PlanarSheetFace(
        id: 'CF_EXT2_TOP',
        label: 'Cover Ext 2 Top Flange',
        role: FaceRole.returnFlange,
        vertices: [CadPoint2D(x2, yMax), CadPoint2D(xEnd, yMax), CadPoint2D(xEnd, yMax + d), CadPoint2D(x2 + d, yMax + d)],
      );

      // 5. Bends:
      final bends = [
        FoldBendLine(
          id: 'C_ROOF_B1',
          p1: CadPoint2D(x1, yMin),
          p2: CadPoint2D(x1, yMax),
          targetAngleDeg: 45.0,
          direction: BendDirection.down,
          radiusMm: 1.5,
          layer: 'BEND_DOWN',
          parentFaceId: 'COVER_MAIN_FACE',
          childFaceId: 'COVER_EXT_FACE_1',
        ),
        FoldBendLine(
          id: 'C_ROOF_B2',
          p1: CadPoint2D(x2, yMin),
          p2: CadPoint2D(x2, yMax),
          targetAngleDeg: 45.0,
          direction: BendDirection.down,
          radiusMm: 1.5,
          layer: 'BEND_DOWN',
          parentFaceId: 'COVER_MAIN_FACE',
          childFaceId: 'COVER_EXT_FACE_2',
        ),
        FoldBendLine(
          id: 'CF_B_MAIN_BOT',
          p1: CadPoint2D(x1, yMin),
          p2: CadPoint2D(x2, yMin),
          targetAngleDeg: 90.0,
          direction: BendDirection.down,
          radiusMm: 1.5,
          layer: 'BEND_DOWN',
          parentFaceId: 'COVER_MAIN_FACE',
          childFaceId: 'CF_MAIN_BOT',
        ),
        FoldBendLine(
          id: 'CF_B_MAIN_TOP',
          p1: CadPoint2D(x2, yMax),
          p2: CadPoint2D(x1, yMax),
          targetAngleDeg: 90.0,
          direction: BendDirection.down,
          radiusMm: 1.5,
          layer: 'BEND_DOWN',
          parentFaceId: 'COVER_MAIN_FACE',
          childFaceId: 'CF_MAIN_TOP',
        ),
        FoldBendLine(
          id: 'CF_B_EXT1_BOT',
          p1: CadPoint2D(xStart, yMin),
          p2: CadPoint2D(x1, yMin),
          targetAngleDeg: 90.0,
          direction: BendDirection.down,
          radiusMm: 1.5,
          layer: 'BEND_DOWN',
          parentFaceId: 'COVER_EXT_FACE_1',
          childFaceId: 'CF_EXT1_BOT',
        ),
        FoldBendLine(
          id: 'CF_B_EXT1_TOP',
          p1: CadPoint2D(x1, yMax),
          p2: CadPoint2D(xStart, yMax),
          targetAngleDeg: 90.0,
          direction: BendDirection.down,
          radiusMm: 1.5,
          layer: 'BEND_DOWN',
          parentFaceId: 'COVER_EXT_FACE_1',
          childFaceId: 'CF_EXT1_TOP',
        ),
        FoldBendLine(
          id: 'CF_B_EXT2_BOT',
          p1: CadPoint2D(x2, yMin),
          p2: CadPoint2D(xEnd, yMin),
          targetAngleDeg: 90.0,
          direction: BendDirection.down,
          radiusMm: 1.5,
          layer: 'BEND_DOWN',
          parentFaceId: 'COVER_EXT_FACE_2',
          childFaceId: 'CF_EXT2_BOT',
        ),
        FoldBendLine(
          id: 'CF_B_EXT2_TOP',
          p1: CadPoint2D(xEnd, yMax),
          p2: CadPoint2D(x2, yMax),
          targetAngleDeg: 90.0,
          direction: BendDirection.down,
          radiusMm: 1.5,
          layer: 'BEND_DOWN',
          parentFaceId: 'COVER_EXT_FACE_2',
          childFaceId: 'CF_EXT2_TOP',
        ),
      ];

      // 6. Outer contour (with 4 V-notches):
      final outerContour = [
        CadPoint2D(xStart, yMin),
        CadPoint2D(xStart, yMin - d),
        CadPoint2D(x1 - d, yMin - d),
        CadPoint2D(x1, yMin),
        CadPoint2D(x1 + d, yMin - d),
        CadPoint2D(x2 - d, yMin - d),
        CadPoint2D(x2, yMin),
        CadPoint2D(x2 + d, yMin - d),
        CadPoint2D(xEnd, yMin - d),
        CadPoint2D(xEnd, yMin),
        CadPoint2D(xEnd, yMax),
        CadPoint2D(xEnd, yMax + d),
        CadPoint2D(x2 + d, yMax + d),
        CadPoint2D(x2, yMax),
        CadPoint2D(x2 - d, yMax + d),
        CadPoint2D(x1 + d, yMax + d),
        CadPoint2D(x1, yMax),
        CadPoint2D(x1 - d, yMax + d),
        CadPoint2D(xStart, yMax + d),
        CadPoint2D(xStart, yMax),
      ];

      final punches = [
        CncPunchPrimitive(
          id: 'COVER_MOUNT_HOLE',
          type: PunchType.roundHole,
          center: CadPoint2D((x1 + x2) / 2.0, (yMin + yMax) / 2.0),
          diameterMm: defaultMountHoleDiameter,
          rotationDeg: 0.0,
          role: CncPunchRole.general,
          parentFaceId: 'COVER_MAIN_FACE',
          showLabel: true,
          isVisible: true,
        ),
      ];

      return DsfDocument(
        productType: '${baseDocument.productType} Cover',
        itemName: '${baseDocument.itemName} Cover',
        material: baseDocument.material,
        outerContour: outerContour,
        bends: bends,
        faces: [mainFace, ext1Face, ext2Face, cfMainBot, cfMainTop, cfExt1Bot, cfExt1Top, cfExt2Bot, cfExt2Top],
        punches: punches,
        baseFaceId: 'COVER_MAIN_FACE',
        parameters: {
          ...baseDocument.parameters,
          'cover_flange_depth': flangeDepth,
          'cover_body_height': bodyHeight,
        },
        metadata: {
          'isCover': true,
          'isTrunkingCover': true,
          'parentProductType': baseDocument.productType,
          'parentItemName': baseDocument.itemName,
          'generator': 'TruFold Studio Cover Engine',
        },
      );
    } else {
      // -------------------------------------------------------------
      // 45° Outside Riser (vertical cheek bends along Y)
      // -------------------------------------------------------------
      // 1. Channel width in X:
      cheekBends.sort((a, b) => ((a.p1.x + a.p2.x) / 2.0).compareTo((b.p1.x + b.p2.x) / 2.0));
      final b1 = cheekBends.first;
      final b2 = cheekBends.last;
      final x1 = math.min((b1.p1.x + b1.p2.x) / 2.0, (b2.p1.x + b2.p2.x) / 2.0);
      final x2 = math.max((b1.p1.x + b1.p2.x) / 2.0, (b2.p1.x + b2.p2.x) / 2.0);
      final xMin = x1 - clearance;
      final xMax = x2 + clearance;

      // 2. Flat top opening span in Y:
      final returnFlanges = baseDocument.bends.where((b) =>
        b.role == BendLineRole.flange || b.layer == 'FLANGE' || b.id.toUpperCase().startsWith('FL')
      ).toList();
      double yStart = 30.0;
      double yKnee = 133.4;
      if (returnFlanges.isNotEmpty) {
        yStart = returnFlanges.map((b) => math.min(b.p1.y, b.p2.y)).reduce(math.min);
        final flMaxY = returnFlanges.map((b) => math.max(b.p1.y, b.p2.y)).reduce(math.max);
        yKnee = flMaxY + 10.0;
      }

      // Check sidewall top rim knee:
      final sidewalls = baseDocument.faces.where((f) => f.role == FaceRole.sideWall).toList();
      for (final wall in sidewalls) {
        for (final fl in returnFlanges) {
          final flangeX = (fl.p1.x + fl.p2.x) / 2.0;
          for (final v in wall.vertices) {
            if ((v.x - flangeX).abs() < 1.0 && v.y > yKnee) {
              yKnee = v.y;
            }
          }
        }
      }

      // 3. Extension length at the single 45° angled end:
      final baseH = (baseDocument.parameters['height'] as num?)?.toDouble() ?? 100.0;
      final deltaH = bodyHeight - baseH;
      final lExt = math.max(20.0, 40.0 + deltaH * 0.5);
      final yEnd = yKnee + lExt;

      // 4. Faces:
      final mainFace = PlanarSheetFace(
        id: 'COVER_MAIN_FACE',
        label: 'Cover Top Plate',
        role: FaceRole.baseFloor,
        isBaseAnchor: true,
        vertices: [CadPoint2D(xMin, yStart), CadPoint2D(xMax, yStart), CadPoint2D(xMax, yKnee), CadPoint2D(xMin, yKnee)],
      );

      final ext1Face = PlanarSheetFace(
        id: 'COVER_EXT_FACE_1',
        label: 'Cover Port 2 Angled Extension (45°)',
        role: FaceRole.returnFlange,
        vertices: [CadPoint2D(xMin, yKnee), CadPoint2D(xMax, yKnee), CadPoint2D(xMax, yEnd), CadPoint2D(xMin, yEnd)],
      );

      final cfMainLeft = PlanarSheetFace(
        id: 'CF_MAIN_LEFT',
        label: 'Cover Center Left Flange',
        role: FaceRole.returnFlange,
        vertices: [CadPoint2D(xMin, yKnee), CadPoint2D(xMin, yStart), CadPoint2D(xMin - d, yStart), CadPoint2D(xMin - d, yKnee - d)],
      );
      final cfMainRight = PlanarSheetFace(
        id: 'CF_MAIN_RIGHT',
        label: 'Cover Center Right Flange',
        role: FaceRole.returnFlange,
        vertices: [CadPoint2D(xMax, yStart), CadPoint2D(xMax, yKnee), CadPoint2D(xMax + d, yKnee - d), CadPoint2D(xMax + d, yStart)],
      );

      final cfExt1Left = PlanarSheetFace(
        id: 'CF_EXT1_LEFT',
        label: 'Cover Ext 1 Left Flange',
        role: FaceRole.returnFlange,
        vertices: [CadPoint2D(xMin, yEnd), CadPoint2D(xMin, yKnee), CadPoint2D(xMin - d, yKnee + d), CadPoint2D(xMin - d, yEnd)],
      );
      final cfExt1Right = PlanarSheetFace(
        id: 'CF_EXT1_RIGHT',
        label: 'Cover Ext 1 Right Flange',
        role: FaceRole.returnFlange,
        vertices: [CadPoint2D(xMax, yKnee), CadPoint2D(xMax, yEnd), CadPoint2D(xMax + d, yEnd), CadPoint2D(xMax + d, yKnee + d)],
      );

      // 5. Bends:
      final bends = [
        FoldBendLine(
          id: 'C_ROOF_B1',
          p1: CadPoint2D(xMin, yKnee),
          p2: CadPoint2D(xMax, yKnee),
          targetAngleDeg: 45.0,
          direction: BendDirection.down,
          radiusMm: 1.5,
          layer: 'BEND_DOWN',
          parentFaceId: 'COVER_MAIN_FACE',
          childFaceId: 'COVER_EXT_FACE_1',
        ),
        FoldBendLine(
          id: 'CF_B_MAIN_LEFT',
          p1: CadPoint2D(xMin, yKnee),
          p2: CadPoint2D(xMin, yStart),
          targetAngleDeg: 90.0,
          direction: BendDirection.down,
          radiusMm: 1.5,
          layer: 'BEND_DOWN',
          parentFaceId: 'COVER_MAIN_FACE',
          childFaceId: 'CF_MAIN_LEFT',
        ),
        FoldBendLine(
          id: 'CF_B_MAIN_RIGHT',
          p1: CadPoint2D(xMax, yStart),
          p2: CadPoint2D(xMax, yKnee),
          targetAngleDeg: 90.0,
          direction: BendDirection.down,
          radiusMm: 1.5,
          layer: 'BEND_DOWN',
          parentFaceId: 'COVER_MAIN_FACE',
          childFaceId: 'CF_MAIN_RIGHT',
        ),
        FoldBendLine(
          id: 'CF_B_EXT1_LEFT',
          p1: CadPoint2D(xMin, yEnd),
          p2: CadPoint2D(xMin, yKnee),
          targetAngleDeg: 90.0,
          direction: BendDirection.down,
          radiusMm: 1.5,
          layer: 'BEND_DOWN',
          parentFaceId: 'COVER_EXT_FACE_1',
          childFaceId: 'CF_EXT1_LEFT',
        ),
        FoldBendLine(
          id: 'CF_B_EXT1_RIGHT',
          p1: CadPoint2D(xMax, yKnee),
          p2: CadPoint2D(xMax, yEnd),
          targetAngleDeg: 90.0,
          direction: BendDirection.down,
          radiusMm: 1.5,
          layer: 'BEND_DOWN',
          parentFaceId: 'COVER_EXT_FACE_1',
          childFaceId: 'CF_EXT1_RIGHT',
        ),
      ];

      // 6. Outer contour (with 2 V-notches):
      final outerContour = [
        CadPoint2D(xMin, yStart),
        CadPoint2D(xMax, yStart),
        CadPoint2D(xMax + d, yStart),
        CadPoint2D(xMax + d, yKnee - d),
        CadPoint2D(xMax, yKnee),
        CadPoint2D(xMax + d, yKnee + d),
        CadPoint2D(xMax + d, yEnd),
        CadPoint2D(xMax, yEnd),
        CadPoint2D(xMin, yEnd),
        CadPoint2D(xMin - d, yEnd),
        CadPoint2D(xMin - d, yKnee + d),
        CadPoint2D(xMin, yKnee),
        CadPoint2D(xMin - d, yKnee - d),
        CadPoint2D(xMin - d, yStart),
      ];

      final punches = [
        CncPunchPrimitive(
          id: 'COVER_MOUNT_HOLE',
          type: PunchType.roundHole,
          center: CadPoint2D((xMin + xMax) / 2.0, (yStart + yKnee) / 2.0),
          diameterMm: defaultMountHoleDiameter,
          rotationDeg: 0.0,
          role: CncPunchRole.general,
          parentFaceId: 'COVER_MAIN_FACE',
          showLabel: true,
          isVisible: true,
        ),
      ];

      return DsfDocument(
        productType: '${baseDocument.productType} Cover',
        itemName: '${baseDocument.itemName} Cover',
        material: baseDocument.material,
        outerContour: outerContour,
        bends: bends,
        faces: [mainFace, ext1Face, cfMainLeft, cfMainRight, cfExt1Left, cfExt1Right],
        punches: punches,
        baseFaceId: 'COVER_MAIN_FACE',
        parameters: {
          ...baseDocument.parameters,
          'cover_flange_depth': flangeDepth,
          'cover_body_height': bodyHeight,
        },
        metadata: {
          'isCover': true,
          'isTrunkingCover': true,
          'parentProductType': baseDocument.productType,
          'parentItemName': baseDocument.itemName,
          'generator': 'TruFold Studio Cover Engine',
        },
      );
    }
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

    // Check if horizontal outside riser (cheek bends run horizontally along X)
    final cheekBends = baseDocument.bends
        .where((b) => (b.targetAngleDeg.abs() - 90.0).abs() < 15.0 && b.role != BendLineRole.flange && !b.id.toUpperCase().startsWith('FL'))
        .toList();
    final isHorizontalOutsideRiser = profile == CmsScalingProfile.outsideRiser &&
        cheekBends.isNotEmpty &&
        (cheekBends.first.p2.x - cheekBends.first.p1.x).abs() > (cheekBends.first.p2.y - cheekBends.first.p1.y).abs();

    // Expand footprint for snug fit over outer body walls.
    final List<CadPoint2D> coverPlateVerts;
    if (profile == CmsScalingProfile.reducer || CmsScalingController.isReducerGeometry(baseDocument)) {
      coverPlateVerts = List<CadPoint2D>.from(baseFloorVerts);
    } else if (profile == CmsScalingProfile.insideRiser || profile == CmsScalingProfile.outsideRiser) {
      if (isHorizontalOutsideRiser) {
        // Horizontal Outside Riser: expand laterally in Y by defaultCoverClearanceOffset for snug fit over side walls,
        // while keeping X boundaries precisely aligned to the flanged area (no elongation beyond flanges).
        coverPlateVerts = [
          CadPoint2D(minX, minY - defaultCoverClearanceOffset),
          CadPoint2D(maxX, minY - defaultCoverClearanceOffset),
          CadPoint2D(maxX, maxY + defaultCoverClearanceOffset),
          CadPoint2D(minX, maxY + defaultCoverClearanceOffset),
        ];
      } else {
        // Vertical Risers: expand laterally in X by defaultCoverClearanceOffset for snug fit over side walls,
        // while keeping Y boundaries precisely aligned to the opening (no elongation beyond the opening).
        coverPlateVerts = [
          CadPoint2D(minX - defaultCoverClearanceOffset, minY),
          CadPoint2D(maxX + defaultCoverClearanceOffset, minY),
          CadPoint2D(maxX + defaultCoverClearanceOffset, maxY),
          CadPoint2D(minX - defaultCoverClearanceOffset, maxY),
        ];
      }
    } else {
      coverPlateVerts = _expandFootprintForSnugFit(
        baseFloorVerts,
        isCcw,
        defaultCoverClearanceOffset,
      );
    }

    // Main top face vertices (expanded footprint for snug fit)
    final mainFaceVerts = List<CadPoint2D>.from(coverPlateVerts);

    // Iterate through every edge of the expanded cover plate
    for (int i = 0; i < n; i++) {
      final p1 = coverPlateVerts[i];
      final p2 = coverPlateVerts[(i + 1) % n];
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
      final portIndex = _identifyPortIndex(p1, p2, midX, midY, profile, isHorizontal: isHorizontalOutsideRiser);
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
        final bool allowDropFlap = profile == CmsScalingProfile.unequalTee ||
            profile == CmsScalingProfile.unequalCross;
        final portH = portHeights[portIndex] ?? bodyHeight;
        final dropFlapLength = bodyHeight - portH;

        if (allowDropFlap && dropFlapLength > 0.5) {
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
          // For anything other than unequal tee and unequal cross,
          // no cover flanges on the Port openings side!
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
        'isTrunkingCover': true,
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
    CmsScalingProfile profile, {
    bool isHorizontal = false,
  }) {
    final dx = (p2.x - p1.x).abs();
    final dy = (p2.y - p1.y).abs();
    final edgeMidX = (p1.x + p2.x) / 2.0;
    final edgeMidY = (p1.y + p2.y) / 2.0;

    if (profile == CmsScalingProfile.equalCross || profile == CmsScalingProfile.unequalCross) {
      // Diagonal edges (dx > 5 && dy > 5) in Cross are 45° corner cheeks!
      final isDiagonal = dx > 5.0 && dy > 5.0;
      if (isDiagonal) return null;

      // 4 orthogonal mouth edges in Cross (per physical CAD port layout):
      // West: Port 1
      if (edgeMidX < midX - 20.0 && dx < 5.0) return 1;
      // North: Port 2
      if (edgeMidY < midY - 20.0 && dy < 5.0) return 2;
      // East: Port 3
      if (edgeMidX > midX + 20.0 && dx < 5.0) return 3;
      // South: Port 4
      if (edgeMidY > midY + 20.0 && dy < 5.0) return 4;
      return null;
    }

    if (profile == CmsScalingProfile.equalTee || profile == CmsScalingProfile.unequalTee) {
      // Diagonal edges in Tee are 45° corner cheeks!
      final isDiagonal = dx > 5.0 && dy > 5.0;
      if (isDiagonal) return null;

      // Top mouth: Port 1 (North)
      if (edgeMidY < midY - 20.0 && dy < 5.0) return 1;
      // Right mouth: Port 2 (East)
      if (edgeMidX > midX + 20.0 && dx < 5.0) return 2;
      // Left mouth: Port 3 (West)
      if (edgeMidX < midX - 20.0 && dx < 5.0) return 3;
      // Bottom horizontal edge: bottom wall (NOT a port!)
      return null;
    }

    if (profile == CmsScalingProfile.insideRiser || profile == CmsScalingProfile.outsideRiser) {
      if (isHorizontal) {
        // In Horizontal Outside Riser (90° outside riser), side walls run along X at minY and maxY.
        // The transverse ends (at minX and maxX) are open port ends (Ports 1 and 2).
        if (dx < 10.0 || (dy > dx && dy > 20.0)) {
          if (edgeMidX < midX) return 1;
          return 2;
        }
        return null; // Wall / cheek edge at minY / maxY (bends down 90°)
      } else {
        // In Risers, side walls run longitudinally, so left & right edges are side walls (return null).
        // The transverse ends (at minY and maxY) are port openings (Ports 1 and 2).
        if (dy < 10.0 || (dx > dy && dx > 20.0)) {
          if (edgeMidY < midY) return 1;
          return 2;
        }
        return null;
      }
    }

    if (profile == CmsScalingProfile.flatBend45) {
      // In 45° Flat Bend:
      // Top horizontal edge (dy < 5.0): Side wall along B1 -> return null.
      // Bottom two angled edges (both endpoints with Y > midY): Side walls along B2/B3 -> return null.
      // Left diagonal edge (connecting bottom to top with edgeMidX < midX): Port 1 opening -> return 1.
      // Right diagonal edge (connecting bottom to top with edgeMidX > midX): Port 2 opening -> return 2.
      if (dy < 5.0) return null;
      if (p1.y > midY && p2.y > midY) return null;
      if (edgeMidX < midX) return 1;
      return 2;
    }

    if (profile == CmsScalingProfile.flatBend90) {
      // In 90° Flat Bend:
      // The 2 open port mouths are the diagonal edges with length >= 70mm (~100mm channel width):
      // - Left diagonal opening (edgeMidX < midX): Port 1
      // - Right diagonal opening (edgeMidX > midX): Port 2
      // All other edges (top/bottom horizontal walls and 45mm angled cheeks) are side walls (return null).
      final edgeLen = math.sqrt(dx * dx + dy * dy);
      if (edgeLen > 70.0 && dx > 20.0 && dy > 20.0) {
        if (edgeMidX < midX) return 1;
        return 2;
      }
      return null;
    }

    if (profile == CmsScalingProfile.reducer) {
      if (dy.abs() < 5.0) {
        return edgeMidY < midY ? 1 : 2;
      }
      return null;
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

  /// Expands [verts] outward by [clearance] mm along outer face normals to ensure
  /// down-folding cover flanges have snug physical clearance over the body's sidewalls.
  static List<CadPoint2D> _expandFootprintForSnugFit(
    List<CadPoint2D> verts,
    bool isCcw,
    double clearance,
  ) {
    final n = verts.length;
    if (n < 3 || clearance <= 0.0) return List<CadPoint2D>.from(verts);

    // Compute unit outward normal and direction for each edge
    final edgeNormals = <CadPoint2D>[];
    final edgeDirs = <CadPoint2D>[];
    final edgePoints = <CadPoint2D>[];
    for (int i = 0; i < n; i++) {
      final p1 = verts[i];
      final p2 = verts[(i + 1) % n];
      final dx = p2.x - p1.x;
      final dy = p2.y - p1.y;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len < 1e-4) {
        edgeNormals.add(const CadPoint2D(0, 0));
        edgeDirs.add(const CadPoint2D(1, 0));
        edgePoints.add(p1);
      } else {
        final ux = dx / len;
        final uy = dy / len;
        edgeDirs.add(CadPoint2D(ux, uy));
        final nx = isCcw ? uy : -uy;
        final ny = isCcw ? -ux : ux;
        edgeNormals.add(CadPoint2D(nx, ny));
        // A point on the offset line
        edgePoints.add(CadPoint2D(p1.x + nx * clearance, p1.y + ny * clearance));
      }
    }

    // Intersect consecutive offset lines L_{i-1} and L_i
    final expanded = <CadPoint2D>[];
    for (int i = 0; i < n; i++) {
      final prevIdx = (i - 1 + n) % n;
      final pA = edgePoints[prevIdx];
      final dA = edgeDirs[prevIdx];
      final pB = edgePoints[i];
      final dB = edgeDirs[i];

      final cross = dA.x * dB.y - dA.y * dB.x;
      if (cross.abs() > 1e-4) {
        final t = ((pB.x - pA.x) * dB.y - (pB.y - pA.y) * dB.x) / cross;
        var ix = pA.x + t * dA.x;
        var iy = pA.y + t * dA.y;

        // Clamp miter distance to prevent spikes on sharp acute corners
        final orig = verts[i];
        final dist = math.sqrt((ix - orig.x) * (ix - orig.x) + (iy - orig.y) * (iy - orig.y));
        final maxMiter = clearance * 2.5;
        if (dist > maxMiter && dist > 1e-4) {
          final scale = maxMiter / dist;
          ix = orig.x + (ix - orig.x) * scale;
          iy = orig.y + (iy - orig.y) * scale;
        }
        expanded.add(CadPoint2D(ix, iy));
      } else {
        // Parallel or collinear consecutive edges
        expanded.add(CadPoint2D(
          verts[i].x + edgeNormals[i].x * clearance,
          verts[i].y + edgeNormals[i].y * clearance,
        ));
      }
    }
    return expanded;
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
    return math.min(maxX - minX, maxY - minY);
  }
}

