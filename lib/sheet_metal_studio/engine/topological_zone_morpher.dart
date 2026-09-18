// =============================================================================
// topological_zone_morpher.dart
//
// Topological Zone Morphing Engine for Sheet Metal Studio (Master Guide #36-#48, P19-P22).
// Enables single DXF templates to parametrically morph without distorting
// invariant corner relief miters, bend notches, or standard tooling hole clusters.
// =============================================================================

import 'dart:math' as math;
import '../models/cad_primitives.dart';
import '../models/cnc_punch_primitive.dart';
import '../models/fold_bend_line.dart';
import '../models/planar_sheet_face.dart';
import '../models/perforation_pattern.dart';
import '../models/dsf_document.dart';
import '../models/sheet_metal_material.dart';
import '../models/template_parameter_definition.dart';
import 'planar_face_decomposer.dart';
import 'cnc_turret_engine.dart';

class TopologicalZoneMorpher {
  /// Morphs a baseline document using the given template definition and target parameter values.
  static DsfDocument morph({
    required DsfDocument baselineDocument,
    required TemplateParameterDefinition template,
    required Map<String, double> targetParameters,
  }) {
    switch (template.templateId) {
      case 'tray_tee':
      case 'equal_tee':
        return _morphTee(baselineDocument, template, targetParameters);
      case 'tray_bend_90':
      case '90_deg_bend':
        return _morphBend90(baselineDocument, template, targetParameters);
      case 'tray_bend_45':
      case '45_deg_bend':
        return _morphBend45(baselineDocument, template, targetParameters);
      case 'tray_reducer':
        return _morphReducer(baselineDocument, template, targetParameters);
      case 'tray_cross':
        return _morphCross(baselineDocument, template, targetParameters);
      case 'tray_straight':
      case 'straight_tray':
        return _morphStraight(baselineDocument, template, targetParameters);
      default:
        // Check document product type or metadata
        final prod = baselineDocument.productType.toLowerCase();
        if (prod.contains('45') && prod.contains('bend')) {
          return _morphBend45(baselineDocument, template, targetParameters);
        }
        return _morphGeneric(baselineDocument, template, targetParameters);
    }
  }

  // ===========================================================================
  // 1. Cable Tray Equal / Unequal Tee Morpher
  // ===========================================================================
  static DsfDocument _morphTee(
    DsfDocument baseline,
    TemplateParameterDefinition template,
    Map<String, double> targetParams,
  ) {
    final origW = template.baselineParameters['width'] ?? 100.0;
    final origBw = template.baselineParameters['branchWidth'] ?? 100.0;
    final origH = template.baselineParameters['height'] ?? 50.0;

    final newW = targetParams['width'] ?? origW;
    final newBw = targetParams['branchWidth'] ?? origBw;
    final newH = targetParams['height'] ?? origH;

    final dW = newW - origW; // delta in main channel width
    final dBw = newBw - origBw; // delta in branch width

    final bounds = _computeBounds(baseline.outerContour);
    final minX = bounds.minX;
    final maxX = bounds.maxX;
    final minY = bounds.minY;
    final midX = (minX + maxX) / 2.0;

    CadPoint2D morphPoint(CadPoint2D pt) {
      double x = pt.x;
      double y = pt.y;

      // X-axis: Expand branch width in the center and shift right arm
      if (x > midX + origBw / 2.0 - 5.0) {
        // Right arm shifts by full dBw
        x += dBw;
      } else if (x > midX - origBw / 2.0 + 5.0) {
        // Inside the branch neck: interpolate or expand
        final t = (x - (midX - origBw / 2.0)) / origBw;
        x += dBw * t.clamp(0.0, 1.0);
      }

      // Y-axis: Expand main bed width and shift branch upward
      if (y > minY + origH + origW - 5.0) {
        // The vertical branch extension shifts upward by dW
        y += dW;
      } else if (y > minY + origH + 5.0) {
        // Main bed floor: scales with dW
        final t = (y - (minY + origH)) / origW;
        y += dW * t.clamp(0.0, 1.0);
      }

      return CadPoint2D(x, y);
    }

    final morphedContour = baseline.outerContour.map(morphPoint).toList();

    final morphedBends = baseline.bends.map((bend) {
      return bend.copyWith(
        p1: morphPoint(bend.p1),
        p2: morphPoint(bend.p2),
      );
    }).toList();

    final morphedPunches = baseline.punches.map((punch) {
      // Coupler punch slots preserve exact size, angle, and shape; only center shifts!
      return punch.copyWith(center: morphPoint(punch.center));
    }).toList();

    // Recompose planar faces
    final decomposed = PlanarFaceDecomposer.decompose(
      outerContour: morphedContour,
      bends: morphedBends,
      cutLines: baseline.cutLines,
    );

    final morphedDoc = baseline.copyWith(
      itemName: 'Tee_${newW.toInt()}x${newH.toInt()}x${newBw.toInt()}',
      outerContour: morphedContour,
      bends: morphedBends,
      punches: morphedPunches,
      faces: decomposed.faces,
      baseFaceId: decomposed.baseFaceId,
    );

    // Re-nest bed perforations if present
    final morphedPatterns = _renestPatterns(
      baseline.perforationPatterns,
      decomposed.faces,
      morphedDoc,
    );

    final newMetadata = Map<String, dynamic>.from(baseline.metadata);
    newMetadata['appliedTemplate'] = template.templateId;
    newMetadata['templateParameters'] = {
      'width': newW,
      'branchWidth': newBw,
      'height': newH,
    };

    return morphedDoc.copyWith(
      perforationPatterns: morphedPatterns,
      metadata: newMetadata,
    );
  }

  // ===========================================================================
  // 2. Cable Tray 90Â° Flat Bend Morpher
  // ===========================================================================
  static DsfDocument _morphBend90(
    DsfDocument baseline,
    TemplateParameterDefinition template,
    Map<String, double> targetParams,
  ) {
    final origW = template.baselineParameters['width'] ?? 100.0;
    final origH = template.baselineParameters['height'] ?? 50.0;
    final origR = template.baselineParameters['radius'] ?? 100.0;

    final newW = targetParams['width'] ?? origW;
    final newH = targetParams['height'] ?? origH;
    final newR = targetParams['radius'] ?? origR;

    final dW = newW - origW;
    final dR = newR - origR;

    final bounds = _computeBounds(baseline.outerContour);
    final minX = bounds.minX;
    final minY = bounds.minY;
    final maxX = bounds.maxX;
    final maxY = bounds.maxY;

    CadPoint2D morphPoint(CadPoint2D pt) {
      double x = pt.x;
      double y = pt.y;

      // 90Â° bend turns from bottom (inlet) to right (outlet)
      // Horizontal arm (outlet) extends along X
      if (x > maxX - origH - 10.0) {
        x += dW + dR;
      } else if (x > minX + origH + origW) {
        x += (dW + dR) * ((x - (minX + origH + origW)) / 100.0).clamp(0.0, 1.0);
      }

      // Vertical arm (inlet) extends along Y
      if (y > maxY - origH - 10.0) {
        y += dW + dR;
      } else if (y > minY + origH + origW) {
        y += (dW + dR) * ((y - (minY + origH + origW)) / 100.0).clamp(0.0, 1.0);
      }

      return CadPoint2D(x, y);
    }

    final morphedContour = baseline.outerContour.map(morphPoint).toList();
    final morphedBends = baseline.bends.map((bend) {
      return bend.copyWith(
        p1: morphPoint(bend.p1),
        p2: morphPoint(bend.p2),
      );
    }).toList();

    final morphedPunches = baseline.punches.map((punch) {
      return punch.copyWith(center: morphPoint(punch.center));
    }).toList();

    final decomposed = PlanarFaceDecomposer.decompose(
      outerContour: morphedContour,
      bends: morphedBends,
      cutLines: baseline.cutLines,
    );

    final morphedDoc = baseline.copyWith(
      itemName: 'Bend90_${newW.toInt()}x${newH.toInt()}',
      outerContour: morphedContour,
      bends: morphedBends,
      punches: morphedPunches,
      faces: decomposed.faces,
      baseFaceId: decomposed.baseFaceId,
    );

    final morphedPatterns = _renestPatterns(
      baseline.perforationPatterns,
      decomposed.faces,
      morphedDoc,
    );

    final newMetadata = Map<String, dynamic>.from(baseline.metadata);
    newMetadata['appliedTemplate'] = template.templateId;
    newMetadata['templateParameters'] = {
      'width': newW,
      'height': newH,
      'radius': newR,
    };

    return morphedDoc.copyWith(
      perforationPatterns: morphedPatterns,
      metadata: newMetadata,
    );
  }

  // ===========================================================================
  // 3. Cable Tray 45° Flat Bend Morpher (Intelligent Bend & Flange Driven)
  // ===========================================================================
  static DsfDocument _morphBend45(
    DsfDocument baseline,
    TemplateParameterDefinition template,
    Map<String, double> targetParams,
  ) {
    final origW = template.baselineParameters['width'] ??
        (baseline.metadata['fittingWidthMm'] as num?)?.toDouble() ??
        100.0;
    final origH = template.baselineParameters['height'] ??
        (baseline.metadata['fittingHeightMm'] as num?)?.toDouble() ??
        50.0;
    final origFlange = template.baselineParameters['flangeWidth'] ??
        template.baselineParameters['flange'] ??
        (baseline.metadata['fittingFlangeMm'] as num?)?.toDouble() ??
        15.0;

    final newW = targetParams['width'] ?? origW;
    final newH = targetParams['height'] ?? origH;
    final newFlange = targetParams['flangeWidth'] ?? targetParams['flange'] ?? origFlange;

    final dW = newW - origW;
    final dH = newH - origH;
    final dFL = newFlange - origFlange;

    final bounds = _computeBounds(baseline.outerContour);
    final xCenter = (bounds.minX + bounds.maxX) / 2.0;

    // Detect if baseline has bend lines (e.g. B1-B5, FL1-FL3)
    if (baseline.bends.isNotEmpty) {
      // pre-computed trig constants for α = 22.5°
      const sinA = 0.3826834323650898;
      const cosA = 0.9238795325112867;

      // -----------------------------------------------------------------------
      // PHASE 1: Extract semantic anchors from DSF bend line data.
      // No hardcoded coordinates — all references are derived from the baseline.
      // -----------------------------------------------------------------------

      // B1 anchor: outer spine fold line (horizontal crease between
      // outer sidewall and miter floor web).
      double yB1 = bounds.minY + (bounds.maxY - bounds.minY) * 0.35;
      for (final b in baseline.bends) {
        if (b.role == BendLineRole.bend && (b.p1.y - b.p2.y).abs() < 2.0) {
          yB1 = (b.p1.y + b.p2.y) / 2.0;
          break;
        }
      }

      // FL1 anchor: outer sidewall return flange fold line.
      double yFL1 = yB1 - (yB1 - bounds.minY) * 0.85;
      for (final b in baseline.bends) {
        if (b.role == BendLineRole.flange &&
            b.p1.y < yB1 - 2.0 &&
            b.p2.y < yB1 - 2.0) {
          yFL1 = (b.p1.y + b.p2.y) / 2.0;
          break;
        }
      }

      // Apex anchor: where B2 and B3 meet on symmetry axis
      double yApex = bounds.minY + (bounds.maxY - bounds.minY) * 0.65;
      for (final b in baseline.bends) {
        if ((b.p1.x - xCenter).abs() < 5.0 && b.p1.y > yB1 + 20.0) {
          yApex = b.p1.y;
          break;
        }
        if ((b.p2.x - xCenter).abs() < 5.0 && b.p2.y > yB1 + 20.0) {
          yApex = b.p2.y;
          break;
        }
      }

      // Arm base anchors: B3 non-apex (left) and B2 non-apex (right)
      CadPoint2D leftArmBase =
          CadPoint2D(bounds.minX + 30.0, yB1 + 80.0);
      CadPoint2D rightArmBase =
          CadPoint2D(bounds.maxX - 30.0, yB1 + 80.0);
      for (final b in baseline.bends) {
        if (b.role != BendLineRole.bend) continue;
        if ((b.p1.x - xCenter).abs() < 5.0 && b.p1.y > yB1 + 20.0) {
          if (b.p2.x < xCenter) {
            leftArmBase = b.p2;
          } else {
            rightArmBase = b.p2;
          }
        } else if ((b.p2.x - xCenter).abs() < 5.0 && b.p2.y > yB1 + 20.0) {
          if (b.p1.x < xCenter) {
            leftArmBase = b.p1;
          } else {
            rightArmBase = b.p1;
          }
        }
      }

      // Direction vectors along B3 (leftArmBase -> apex) and B2 (rightArmBase -> apex)
      final leftArmVecX = xCenter - leftArmBase.x;
      final leftArmVecY = yApex - leftArmBase.y;
      final leftArmLen =
          math.sqrt(leftArmVecX * leftArmVecX + leftArmVecY * leftArmVecY);
      final leftArmDirX = leftArmLen > 0 ? leftArmVecX / leftArmLen : 0.98606;
      final leftArmDirY = leftArmLen > 0 ? leftArmVecY / leftArmLen : 0.16631;

      final rightArmVecX = xCenter - rightArmBase.x;
      final rightArmVecY = yApex - rightArmBase.y;
      final rightArmLen =
          math.sqrt(rightArmVecX * rightArmVecX + rightArmVecY * rightArmVecY);
      final rightArmDirX = rightArmLen > 0 ? rightArmVecX / rightArmLen : -0.98606;
      final rightArmDirY = rightArmLen > 0 ? rightArmVecY / rightArmLen : 0.16631;

      // Outward normal vectors perpendicular to B3 and B2 (pointing into the walls)
      final nB3X = -leftArmDirY;
      final nB3Y = leftArmDirX;

      final nB2X = rightArmDirY;
      final nB2Y = -rightArmDirX;

      // Apex Y factor when Width increases (miter geometry):
      final slope = leftArmVecX.abs() > 1e-3 ? leftArmVecY / leftArmVecX.abs() : 0.16866;
      final dyApexFactor = cosA + sinA * slope;

      // Flange-root reference distances (from B3/B2 to FL3/FL2 endpoints)
      double distFlangeRootLeft1 = 95.5;
      double distFlangeRootLeft2 = 110.5;
      double distFlangeRootRight1 = 95.5;
      double distFlangeRootRight2 = 110.5;
      for (final b in baseline.bends) {
        if (b.role != BendLineRole.flange) continue;
        final bMidY = (b.p1.y + b.p2.y) / 2.0;
        if (bMidY > yB1 + 20.0) {
          final midX = (b.p1.x + b.p2.x) / 2.0;
          if (midX < xCenter) {
            final d1 = (b.p1.x - leftArmBase.x) * nB3X + (b.p1.y - leftArmBase.y) * nB3Y;
            final d2 = (b.p2.x - leftArmBase.x) * nB3X + (b.p2.y - leftArmBase.y) * nB3Y;
            distFlangeRootLeft1 = math.min(d1, d2);
            distFlangeRootLeft2 = math.max(d1, d2);
          } else {
            final d1 = (b.p1.x - rightArmBase.x) * nB2X + (b.p1.y - rightArmBase.y) * nB2Y;
            final d2 = (b.p2.x - rightArmBase.x) * nB2X + (b.p2.y - rightArmBase.y) * nB2Y;
            distFlangeRootRight1 = math.min(d1, d2);
            distFlangeRootRight2 = math.max(d1, d2);
          }
        }
      }

      // -----------------------------------------------------------------------
      // PHASE 2: 3D-driven semantic zone transform function.
      // -----------------------------------------------------------------------

      CadPoint2D morphPoint(CadPoint2D pt) {
        final px = pt.x;
        final py = pt.y;

        // --- Zone 1: Outer Wall (py <= yB1 + 1.0) ---
        // Width  → spine length is preserved (no elongation of drawing length!).
        // Height → extends downwards along -Y away from B1 by dH * tInlet.
        // Flange → distal lip (py <= yFL1) extends downward by extra dFL.
        if (py <= yB1 + 1.0) {
          double nx = px;
          double ny = py;
          if (py < yB1 - 1.0) {
            final tInlet = ((yB1 - py) / (yB1 - yFL1)).clamp(0.0, 1.0);
            ny -= dH * tInlet;
            if (py <= yFL1 + 1.0) {
              ny -= dFL;
            }
          }
          return CadPoint2D(nx, ny);
        }

        // --- Zone 2: Apex & Symmetry Axis ((px - xCenter).abs() < 2.0) ---
        // Width  → apex shifts upward by dW * dyApexFactor (miter geometry).
        // Height → floor apex is stationary (Z = 0 floor anchor).
        // Flange → 0.
        if ((px - xCenter).abs() < 2.0 && py > yB1 + 20.0) {
          return CadPoint2D(xCenter, py + dW * dyApexFactor);
        }

        // --- Zone 3: Left Arm (px < xCenter - 1.0) ---
        if (px < xCenter - 1.0) {
          final relX = px - leftArmBase.x;
          final relY = py - leftArmBase.y;

          // Projection parameter s along B3: s=0 at leftArmBase, s=1 at apex
          final sRaw = (relX * leftArmDirX + relY * leftArmDirY) / leftArmLen;
          final s = sRaw.clamp(0.0, 1.0);

          // Perpendicular distance outward from B3 line into the wall
          final distFromB3 = relX * nB3X + relY * nB3Y;

          // 1. Width shift: Port 1 floor edge expands by dW along (-sinA, cosA).
          // At s=0 (leftArmBase): shift = (-dW*sinA, dW*cosA).
          // At s=1 (apex): shift = (0, dW*dyApexFactor).
          final wShiftX = (1.0 - s) * (-dW * sinA);
          final wShiftY = (1.0 - s) * (dW * cosA) + s * (dW * dyApexFactor);

          // 2. Height shift: wall extends outward along nB3 by dH * tH.
          // Points on B3 (distFromB3 <= 0) stay anchored to the floor web!
          // Points at FL3 shift fully by dH * nB3.
          final distFL = (1.0 - s) * distFlangeRootLeft1 + s * distFlangeRootLeft2;
          double hShiftX = 0.0;
          double hShiftY = 0.0;
          if (distFromB3 > 1.0) {
            final tH = (distFromB3 / (distFL - 1.0)).clamp(0.0, 1.0);
            hShiftX += dH * tH * nB3X;
            hShiftY += dH * tH * nB3Y;

            // 3. Flange shift: distal flange lip beyond FL3 fold line extends by dFL
            if (distFromB3 > distFL + 1.0) {
              hShiftX += dFL * nB3X;
              hShiftY += dFL * nB3Y;
            }
          }

          return CadPoint2D(px + wShiftX + hShiftX, py + wShiftY + hShiftY);
        }

        // --- Zone 4: Right Arm (px > xCenter + 1.0) ---
        if (px > xCenter + 1.0) {
          final relX = px - rightArmBase.x;
          final relY = py - rightArmBase.y;

          final sRaw = (relX * rightArmDirX + relY * rightArmDirY) / rightArmLen;
          final s = sRaw.clamp(0.0, 1.0);

          final distFromB2 = relX * nB2X + relY * nB2Y;

          // 1. Width shift: Port 2 floor edge expands by dW along (+sinA, cosA).
          // At s=0 (rightArmBase): shift = (+dW*sinA, dW*cosA).
          // At s=1 (apex): shift = (0, dW*dyApexFactor).
          final wShiftX = (1.0 - s) * (dW * sinA);
          final wShiftY = (1.0 - s) * (dW * cosA) + s * (dW * dyApexFactor);

          // 2. Height shift: wall extends outward along nB2 by dH * tH.
          final distFL = (1.0 - s) * distFlangeRootRight1 + s * distFlangeRootRight2;
          double hShiftX = 0.0;
          double hShiftY = 0.0;
          if (distFromB2 > 1.0) {
            final tH = (distFromB2 / (distFL - 1.0)).clamp(0.0, 1.0);
            hShiftX += dH * tH * nB2X;
            hShiftY += dH * tH * nB2Y;

            // 3. Flange shift
            if (distFromB2 > distFL + 1.0) {
              hShiftX += dFL * nB2X;
              hShiftY += dFL * nB2Y;
            }
          }

          return CadPoint2D(px + wShiftX + hShiftX, py + wShiftY + hShiftY);
        }

        // --- Zone 5: Fallback (on-axis points above inlet, not the apex) ---
        return CadPoint2D(xCenter, py + dW * dyApexFactor);
      }

      final morphedContour = baseline.outerContour.map(morphPoint).toList();
      final morphedBends = baseline.bends.map((b) => b.copyWith(
        p1: morphPoint(b.p1),
        p2: morphPoint(b.p2),
      )).toList();

      // Guard rigid coupler punches: dimensions unchanged, translate center only
      final morphedPunches = baseline.punches.map((p) {
        final newCenter = morphPoint(p.center);
        return p.copyWith(
          center: newCenter,
          widthMm: p.widthMm,
          lengthMm: p.lengthMm,
          diameterMm: p.diameterMm,
          rotationDeg: p.rotationDeg,
          role: p.type == PunchType.obroundSlot || p.isCoupler
              ? CncPunchRole.coupler
              : p.role,
        );
      }).toList();

      final morphedFaces = baseline.faces.map((f) => f.copyWith(
        vertices: f.vertices.map(morphPoint).toList(),
      )).toList();

      final newMetadata = Map<String, dynamic>.from(baseline.metadata);
      newMetadata['appliedTemplate'] = template.templateId;
      newMetadata['templateParameters'] = {
        'width': newW,
        'height': newH,
        'flangeWidth': newFlange,
      };

      return baseline.copyWith(
        itemName: 'Bend45_${newW.toInt()}x${newH.toInt()}',
        outerContour: morphedContour,
        bends: morphedBends,
        punches: morphedPunches,
        faces: morphedFaces,
        metadata: newMetadata,
        parameters: {
          'width': newW,
          'height': newH,
          'flangeWidth': newFlange,
        },
      );
    }

    // Fallback for simple 2D raw perimeter without bends
    CadPoint2D morphPoint(CadPoint2D pt) {
      double x = pt.x;
      double y = pt.y;
      if (x > xCenter) {
        x += dW * 0.7071;
        y += dW * 0.7071;
      }
      return CadPoint2D(x, y);
    }

    final morphedContour = baseline.outerContour.map(morphPoint).toList();
    final morphedBends = baseline.bends.map((bend) {
      return bend.copyWith(
        p1: morphPoint(bend.p1),
        p2: morphPoint(bend.p2),
      );
    }).toList();

    final morphedPunches = baseline.punches.map((punch) {
      return punch.copyWith(center: morphPoint(punch.center));
    }).toList();

    final decomposed = PlanarFaceDecomposer.decompose(
      outerContour: morphedContour,
      bends: morphedBends,
      cutLines: baseline.cutLines,
    );

    final newMetadata = Map<String, dynamic>.from(baseline.metadata);
    newMetadata['appliedTemplate'] = template.templateId;
    newMetadata['templateParameters'] = {
      'width': newW,
      'height': newH,
    };

    return baseline.copyWith(
      itemName: 'Bend45_${newW.toInt()}x${newH.toInt()}',
      outerContour: morphedContour,
      bends: morphedBends,
      punches: morphedPunches,
      faces: decomposed.faces,
      baseFaceId: decomposed.baseFaceId,
      metadata: newMetadata,
    );
  }

  // ===========================================================================
  // 4. Cable Tray Concentric / Eccentric Reducer Morpher
  // ===========================================================================
  static DsfDocument _morphReducer(
    DsfDocument baseline,
    TemplateParameterDefinition template,
    Map<String, double> targetParams,
  ) {
    final origWin = template.baselineParameters['widthIn'] ?? 100.0;
    final origWout = template.baselineParameters['widthOut'] ?? 50.0;
    final origH = template.baselineParameters['height'] ?? 50.0;
    final origL = template.baselineParameters['length'] ?? 150.0;

    final newWin = targetParams['widthIn'] ?? origWin;
    final newWout = targetParams['widthOut'] ?? origWout;
    final newH = targetParams['height'] ?? origH;
    final newL = targetParams['length'] ?? origL;

    final dWin = newWin - origWin;
    final dWout = newWout - origWout;
    final dL = newL - origL;

    final bounds = _computeBounds(baseline.outerContour);
    final minX = bounds.minX;
    final maxX = bounds.maxX;
    final totalX = maxX - minX;

    CadPoint2D morphPoint(CadPoint2D pt) {
      double x = pt.x;
      double y = pt.y;

      // X position ratio (0.0 at input side, 1.0 at output side)
      final tx = ((x - minX) / (totalX > 0 ? totalX : 1.0)).clamp(0.0, 1.0);

      // Interpolated width delta at this X coordinate
      final localDeltaW = dWin * (1.0 - tx) + dWout * tx;

      // Stretch length along X
      x += dL * tx;

      // Symmetrically adjust width along Y
      final midY = (bounds.minY + bounds.maxY) / 2.0;
      if (y > midY) {
        y += localDeltaW / 2.0;
      } else {
        y -= localDeltaW / 2.0;
      }

      return CadPoint2D(x, y);
    }

    final morphedContour = baseline.outerContour.map(morphPoint).toList();
    final morphedBends = baseline.bends.map((bend) {
      return bend.copyWith(
        p1: morphPoint(bend.p1),
        p2: morphPoint(bend.p2),
      );
    }).toList();

    final morphedPunches = baseline.punches.map((punch) {
      return punch.copyWith(center: morphPoint(punch.center));
    }).toList();

    final decomposed = PlanarFaceDecomposer.decompose(
      outerContour: morphedContour,
      bends: morphedBends,
      cutLines: baseline.cutLines,
    );

    final newMetadata = Map<String, dynamic>.from(baseline.metadata);
    newMetadata['appliedTemplate'] = template.templateId;
    newMetadata['templateParameters'] = {
      'widthIn': newWin,
      'widthOut': newWout,
      'height': newH,
      'length': newL,
    };

    return baseline.copyWith(
      itemName: 'Reducer_${newWin.toInt()}x${newWout.toInt()}x${newH.toInt()}',
      outerContour: morphedContour,
      bends: morphedBends,
      punches: morphedPunches,
      faces: decomposed.faces,
      baseFaceId: decomposed.baseFaceId,
      metadata: newMetadata,
    );
  }

  // ===========================================================================
  // 5. Cable Tray Equal / Unequal Cross Morpher
  // ===========================================================================
  static DsfDocument _morphCross(
    DsfDocument baseline,
    TemplateParameterDefinition template,
    Map<String, double> targetParams,
  ) {
    final origWmain = template.baselineParameters['widthMain'] ?? 100.0;
    final origWbranch = template.baselineParameters['widthBranch'] ?? 100.0;
    final origH = template.baselineParameters['height'] ?? 50.0;

    final newWmain = targetParams['widthMain'] ?? origWmain;
    final newWbranch = targetParams['widthBranch'] ?? origWbranch;
    final newH = targetParams['height'] ?? origH;

    final dWmain = newWmain - origWmain;
    final dWbranch = newWbranch - origWbranch;

    final bounds = _computeBounds(baseline.outerContour);
    final midX = (bounds.minX + bounds.maxX) / 2.0;
    final midY = (bounds.minY + bounds.maxY) / 2.0;

    CadPoint2D morphPoint(CadPoint2D pt) {
      double x = pt.x;
      double y = pt.y;

      // Expand horizontal arms
      if (x > midX + origWbranch / 2.0) {
        x += dWbranch / 2.0;
      } else if (x < midX - origWbranch / 2.0) {
        x -= dWbranch / 2.0;
      }

      // Expand vertical arms
      if (y > midY + origWmain / 2.0) {
        y += dWmain / 2.0;
      } else if (y < midY - origWmain / 2.0) {
        y -= dWmain / 2.0;
      }

      return CadPoint2D(x, y);
    }

    final morphedContour = baseline.outerContour.map(morphPoint).toList();
    final morphedBends = baseline.bends.map((bend) {
      return bend.copyWith(
        p1: morphPoint(bend.p1),
        p2: morphPoint(bend.p2),
      );
    }).toList();

    final morphedPunches = baseline.punches.map((punch) {
      return punch.copyWith(center: morphPoint(punch.center));
    }).toList();

    final decomposed = PlanarFaceDecomposer.decompose(
      outerContour: morphedContour,
      bends: morphedBends,
      cutLines: baseline.cutLines,
    );

    final newMetadata = Map<String, dynamic>.from(baseline.metadata);
    newMetadata['appliedTemplate'] = template.templateId;
    newMetadata['templateParameters'] = {
      'widthMain': newWmain,
      'widthBranch': newWbranch,
      'height': newH,
    };

    return baseline.copyWith(
      itemName: 'Cross_${newWmain.toInt()}x${newWbranch.toInt()}x${newH.toInt()}',
      outerContour: morphedContour,
      bends: morphedBends,
      punches: morphedPunches,
      faces: decomposed.faces,
      baseFaceId: decomposed.baseFaceId,
      metadata: newMetadata,
    );
  }

  // ===========================================================================
  // 6. Straight Cable Tray Channel Morpher
  // ===========================================================================
  static DsfDocument _morphStraight(
    DsfDocument baseline,
    TemplateParameterDefinition template,
    Map<String, double> targetParams,
  ) {
    final origW = template.baselineParameters['width'] ?? 100.0;
    final origH = template.baselineParameters['height'] ?? 50.0;
    final origL = template.baselineParameters['length'] ?? 1000.0;
    final origFlange = template.baselineParameters['flange'] ?? 15.0;

    final newW = targetParams['width'] ?? origW;
    final newH = targetParams['height'] ?? origH;
    final newL = targetParams['length'] ?? origL;
    final newFlange = targetParams['flange'] ?? origFlange;

    // Use built-in sample cable tray generator with exact new dimensions
    final generated = DsfDocument.sampleCableTray(
      width: newW,
      height: newH,
      length: newL,
      flange: newFlange,
      thickness: baseline.material.thicknessMm,
    );

    final newMetadata = Map<String, dynamic>.from(baseline.metadata);
    newMetadata['appliedTemplate'] = template.templateId;
    newMetadata['templateParameters'] = {
      'width': newW,
      'height': newH,
      'length': newL,
      'flange': newFlange,
    };

    return generated.copyWith(
      metadata: newMetadata,
      material: baseline.material,
      perforationPatterns: baseline.perforationPatterns,
    );
  }

  // ===========================================================================
  // 7. Generic Zone Rule Fallback Morpher
  // ===========================================================================
  static DsfDocument _morphGeneric(
    DsfDocument baseline,
    TemplateParameterDefinition template,
    Map<String, double> targetParams,
  ) {
    final bounds = _computeBounds(baseline.outerContour);
    final totalW = bounds.maxX - bounds.minX;
    final totalL = bounds.maxY - bounds.minY;

    CadPoint2D morphPoint(CadPoint2D pt) {
      double x = pt.x;
      double y = pt.y;

      final nx = totalW > 0 ? (pt.x - bounds.minX) / totalW : 0.5;
      final ny = totalL > 0 ? (pt.y - bounds.minY) / totalL : 0.5;

      for (final rule in template.zoneRules) {
        final b = rule.normalizedBounds;
        final inZone = b == null ||
            (nx >= b[0] && nx <= b[1] && ny >= b[2] && ny <= b[3]);

        if (inZone) {
          final origVal = template.baselineParameters[rule.drivingParamKey] ?? 100.0;
          final newVal = targetParams[rule.drivingParamKey] ?? origVal;
          final delta = newVal - origVal;

          x += delta * rule.dxFactor;
          y += delta * rule.dyFactor;
        }
      }

      return CadPoint2D(x, y);
    }

    final morphedContour = baseline.outerContour.map(morphPoint).toList();
    final morphedBends = baseline.bends.map((b) => b.copyWith(
      p1: morphPoint(b.p1),
      p2: morphPoint(b.p2),
    )).toList();
    final morphedPunches = baseline.punches.map((p) => p.copyWith(
      center: morphPoint(p.center),
    )).toList();

    final decomposed = PlanarFaceDecomposer.decompose(
      outerContour: morphedContour,
      bends: morphedBends,
      cutLines: baseline.cutLines,
    );

    return baseline.copyWith(
      outerContour: morphedContour,
      bends: morphedBends,
      punches: morphedPunches,
      faces: decomposed.faces,
      baseFaceId: decomposed.baseFaceId,
    );
  }

  // ===========================================================================
  // Helper: Re-nest Perforations on Morphed Floor Faces
  // ===========================================================================
  static List<PerforationPattern> _renestPatterns(
    List<PerforationPattern> originalPatterns,
    List<PlanarSheetFace> updatedFaces,
    DsfDocument doc,
  ) {
    if (originalPatterns.isEmpty) return const [];

    final updated = <PerforationPattern>[];
    for (final pattern in originalPatterns) {
      PlanarSheetFace? targetFace;
      try {
        targetFace = updatedFaces.firstWhere((f) => f.id == pattern.targetFaceId);
      } catch (_) {
        targetFace = updatedFaces.firstWhere(
          (f) => f.isBaseAnchor || f.role == FaceRole.baseFloor,
          orElse: () => updatedFaces.first,
        );
      }

      final renested = CncTurretEngine.autoNestPerforationOnFace(
        face: targetFace,
        doc: doc,
        holeType: pattern.holeType,
        slotWidth: pattern.slotWidthMm,
        slotLength: pattern.slotLengthMm,
        diameterMm: pattern.diameterMm,
        rotationDeg: pattern.rotationDeg,
        staggered: pattern.staggered,
      );

      updated.add(pattern.copyWith(
        anchor: renested.anchor,
        countX: renested.countX,
        countY: renested.countY,
        pitchX: renested.pitchX,
        pitchY: renested.pitchY,
        targetFaceId: targetFace.id,
      ));
    }

    return updated;
  }

  // ===========================================================================
  // Helper: Bounding Box Computation
  // ===========================================================================
  static ({double minX, double maxX, double minY, double maxY}) _computeBounds(
    List<CadPoint2D> pts,
  ) {
    if (pts.isEmpty) return (minX: 0.0, maxX: 100.0, minY: 0.0, maxY: 100.0);
    double minX = pts.first.x;
    double maxX = pts.first.x;
    double minY = pts.first.y;
    double maxY = pts.first.y;

    for (final p in pts) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }

    return (minX: minX, maxX: maxX, minY: minY, maxY: maxY);
  }

  // ===========================================================================
  // Factory Baseline Document Generators for Catalog Fittings
  // ===========================================================================

  /// Generates a clean baseline DSF for an Equal/Unequal Cable Tray Tee
  static DsfDocument createBaselineTee({
    double width = 100.0,
    double branchWidth = 100.0,
    double height = 50.0,
    double thickness = 1.5,
  }) {
    final totalMainLength = branchWidth + 200.0; // 50mm left margin + branch + 50mm right
    final mainRunY = height;
    final branchEndY = mainRunY + width + 100.0;

    // Outer contour with standard 45Â° corner relief cutouts at flange intersections
    final contour = <CadPoint2D>[
      // Bottom main wall
      CadPoint2D(0, 0),
      CadPoint2D(totalMainLength, 0),
      CadPoint2D(totalMainLength, height),
      // Right coupler tab
      CadPoint2D(totalMainLength, height + width),
      CadPoint2D(totalMainLength, height + width + height),
      CadPoint2D(totalMainLength - 50.0, height + width + height),
      // Branch right corner miter
      CadPoint2D(totalMainLength - 50.0, branchEndY),
      CadPoint2D(50.0 + branchWidth, branchEndY),
      // Branch top coupler tab
      CadPoint2D(50.0, branchEndY),
      CadPoint2D(50.0, height + width + height),
      // Left coupler tab
      CadPoint2D(0, height + width + height),
      CadPoint2D(0, height + width),
      CadPoint2D(0, height),
    ];

    final bends = <FoldBendLine>[
      // Bottom main wall bend
      FoldBendLine(
        id: 'BEND_MAIN_BOT',
        p1: CadPoint2D(0, height),
        p2: CadPoint2D(totalMainLength, height),
        targetAngleDeg: 90.0,
        radiusMm: thickness,
        direction: BendDirection.up,
      ),
      // Top main wall left bend
      FoldBendLine(
        id: 'BEND_MAIN_TOP_L',
        p1: CadPoint2D(0, height + width),
        p2: CadPoint2D(50.0, height + width),
        targetAngleDeg: 90.0,
        radiusMm: thickness,
        direction: BendDirection.up,
      ),
      // Top main wall right bend
      FoldBendLine(
        id: 'BEND_MAIN_TOP_R',
        p1: CadPoint2D(50.0 + branchWidth, height + width),
        p2: CadPoint2D(totalMainLength, height + width),
        targetAngleDeg: 90.0,
        radiusMm: thickness,
        direction: BendDirection.up,
      ),
      // Branch left wall bend
      FoldBendLine(
        id: 'BEND_BRANCH_L',
        p1: CadPoint2D(50.0, height + width),
        p2: CadPoint2D(50.0, branchEndY),
        targetAngleDeg: 90.0,
        radiusMm: thickness,
        direction: BendDirection.up,
      ),
      // Branch right wall bend
      FoldBendLine(
        id: 'BEND_BRANCH_R',
        p1: CadPoint2D(50.0 + branchWidth, height + width),
        p2: CadPoint2D(50.0 + branchWidth, branchEndY),
        targetAngleDeg: 90.0,
        radiusMm: thickness,
        direction: BendDirection.up,
      ),
    ];

    // Standard coupler punches (7x30 obround slots) on flange ends
    final punches = <CncPunchPrimitive>[
      // Left coupler slots
      CncPunchPrimitive.obround(
        id: 'PUNCH_COUP_L1',
        center: CadPoint2D(15.0, height / 2.0),
        widthMm: 30.0,
        lengthMm: 7.0,
      ),
      CncPunchPrimitive.obround(
        id: 'PUNCH_COUP_L2',
        center: CadPoint2D(15.0, height + width + height / 2.0),
        widthMm: 30.0,
        lengthMm: 7.0,
      ),
      // Right coupler slots
      CncPunchPrimitive.obround(
        id: 'PUNCH_COUP_R1',
        center: CadPoint2D(totalMainLength - 15.0, height / 2.0),
        widthMm: 30.0,
        lengthMm: 7.0,
      ),
      CncPunchPrimitive.obround(
        id: 'PUNCH_COUP_R2',
        center: CadPoint2D(totalMainLength - 15.0, height + width + height / 2.0),
        widthMm: 30.0,
        lengthMm: 7.0,
      ),
      // Branch top coupler slots
      CncPunchPrimitive.obround(
        id: 'PUNCH_COUP_B1',
        center: CadPoint2D(35.0, branchEndY - 15.0),
        widthMm: 7.0,
        lengthMm: 30.0,
        rotationDeg: 90.0,
      ),
      CncPunchPrimitive.obround(
        id: 'PUNCH_COUP_B2',
        center: CadPoint2D(50.0 + branchWidth + 15.0, branchEndY - 15.0),
        widthMm: 7.0,
        lengthMm: 30.0,
        rotationDeg: 90.0,
      ),
    ];

    final decomposed = PlanarFaceDecomposer.decompose(
      outerContour: contour,
      bends: bends,
    );

    return DsfDocument(
      productType: 'Cable Tray Tee',
      itemName: 'Tee_${width.toInt()}x${height.toInt()}x${branchWidth.toInt()}',
      material: SheetMetalMaterial(thicknessMm: thickness),
      outerContour: contour,
      bends: bends,
      punches: punches,
      faces: decomposed.faces,
      baseFaceId: decomposed.baseFaceId,
      metadata: {
        'appliedTemplate': 'tray_tee',
        'templateParameters': {
          'width': width,
          'branchWidth': branchWidth,
          'height': height,
        },
      },
    );
  }

  /// Generates a clean baseline DSF for a 90Â° Cable Tray Flat Bend
  static DsfDocument createBaselineBend90({
    double width = 100.0,
    double height = 50.0,
    double radius = 100.0,
    double thickness = 1.5,
  }) {
    final straightLead = 50.0;
    final totalSize = straightLead + radius + width + height;

    final contour = <CadPoint2D>[
      CadPoint2D(0, 0),
      CadPoint2D(straightLead + radius + width, 0),
      CadPoint2D(straightLead + radius + width, height),
      CadPoint2D(totalSize, height),
      CadPoint2D(totalSize, height + width),
      CadPoint2D(height + width, totalSize),
      CadPoint2D(height, totalSize),
      CadPoint2D(height, straightLead + radius + width),
      CadPoint2D(0, straightLead + radius + width),
    ];

    final bends = <FoldBendLine>[
      FoldBendLine(
        id: 'BEND_B90_OUTER',
        p1: CadPoint2D(height, height),
        p2: CadPoint2D(totalSize - height, height),
        targetAngleDeg: 90.0,
        radiusMm: thickness,
        direction: BendDirection.up,
      ),
      FoldBendLine(
        id: 'BEND_B90_INNER',
        p1: CadPoint2D(height, height),
        p2: CadPoint2D(height, totalSize - height),
        targetAngleDeg: 90.0,
        radiusMm: thickness,
        direction: BendDirection.up,
      ),
    ];

    final punches = <CncPunchPrimitive>[
      CncPunchPrimitive.obround(
        id: 'PUNCH_B90_1',
        center: CadPoint2D(straightLead / 2.0, height / 2.0),
        widthMm: 30.0,
        lengthMm: 7.0,
      ),
      CncPunchPrimitive.obround(
        id: 'PUNCH_B90_2',
        center: CadPoint2D(height / 2.0, totalSize - straightLead / 2.0),
        widthMm: 7.0,
        lengthMm: 30.0,
        rotationDeg: 90.0,
      ),
    ];

    final decomposed = PlanarFaceDecomposer.decompose(
      outerContour: contour,
      bends: bends,
    );

    return DsfDocument(
      productType: 'Cable Tray 90Â° Bend',
      itemName: 'Bend90_${width.toInt()}x${height.toInt()}',
      material: SheetMetalMaterial(thicknessMm: thickness),
      outerContour: contour,
      bends: bends,
      punches: punches,
      faces: decomposed.faces,
      baseFaceId: decomposed.baseFaceId,
      metadata: {
        'appliedTemplate': 'tray_bend_90',
        'templateParameters': {
          'width': width,
          'height': height,
          'radius': radius,
        },
      },
    );
  }

  /// Generates a clean baseline DSF for a Cable Tray Reducer
  static DsfDocument createBaselineReducer({
    double widthIn = 100.0,
    double widthOut = 50.0,
    double height = 50.0,
    double length = 150.0,
    double thickness = 1.5,
  }) {
    final straightLead = 40.0;
    final totalLen = straightLead * 2 + length;
    final maxHalfW = widthIn / 2.0 + height;
    final minHalfW = widthOut / 2.0 + height;

    final contour = <CadPoint2D>[
      CadPoint2D(0, -maxHalfW),
      CadPoint2D(straightLead, -maxHalfW),
      CadPoint2D(straightLead + length, -minHalfW),
      CadPoint2D(totalLen, -minHalfW),
      CadPoint2D(totalLen, minHalfW),
      CadPoint2D(straightLead + length, minHalfW),
      CadPoint2D(straightLead, maxHalfW),
      CadPoint2D(0, maxHalfW),
    ];

    final bends = <FoldBendLine>[
      FoldBendLine(
        id: 'BEND_RED_BOT',
        p1: CadPoint2D(0, -widthIn / 2.0),
        p2: CadPoint2D(totalLen, -widthOut / 2.0),
        targetAngleDeg: 90.0,
        radiusMm: thickness,
        direction: BendDirection.up,
      ),
      FoldBendLine(
        id: 'BEND_RED_TOP',
        p1: CadPoint2D(0, widthIn / 2.0),
        p2: CadPoint2D(totalLen, widthOut / 2.0),
        targetAngleDeg: 90.0,
        radiusMm: thickness,
        direction: BendDirection.up,
      ),
    ];

    final punches = <CncPunchPrimitive>[
      CncPunchPrimitive.obround(
        id: 'PUNCH_RED_IN_1',
        center: CadPoint2D(straightLead / 2.0, -widthIn / 2.0 - height / 2.0),
        widthMm: 25.0,
        lengthMm: 7.0,
      ),
      CncPunchPrimitive.obround(
        id: 'PUNCH_RED_IN_2',
        center: CadPoint2D(straightLead / 2.0, widthIn / 2.0 + height / 2.0),
        widthMm: 25.0,
        lengthMm: 7.0,
      ),
      CncPunchPrimitive.obround(
        id: 'PUNCH_RED_OUT_1',
        center: CadPoint2D(totalLen - straightLead / 2.0, -widthOut / 2.0 - height / 2.0),
        widthMm: 25.0,
        lengthMm: 7.0,
      ),
      CncPunchPrimitive.obround(
        id: 'PUNCH_RED_OUT_2',
        center: CadPoint2D(totalLen - straightLead / 2.0, widthOut / 2.0 + height / 2.0),
        widthMm: 25.0,
        lengthMm: 7.0,
      ),
    ];

    final decomposed = PlanarFaceDecomposer.decompose(
      outerContour: contour,
      bends: bends,
    );

    return DsfDocument(
      productType: 'Cable Tray Reducer',
      itemName: 'Reducer_${widthIn.toInt()}x${widthOut.toInt()}x${height.toInt()}',
      material: SheetMetalMaterial(thicknessMm: thickness),
      outerContour: contour,
      bends: bends,
      punches: punches,
      faces: decomposed.faces,
      baseFaceId: decomposed.baseFaceId,
      metadata: {
        'appliedTemplate': 'tray_reducer',
        'templateParameters': {
          'widthIn': widthIn,
          'widthOut': widthOut,
          'height': height,
          'length': length,
        },
      },
    );
  }

  /// Generates a clean baseline DSF for a Straight Cable Tray
  static DsfDocument createBaselineStraight({
    double width = 100.0,
    double height = 50.0,
    double length = 1000.0,
    double thickness = 1.5,
  }) {
    return DsfDocument.sampleCableTray(
      width: width,
      height: height,
      length: length,
      flange: 15.0,
      thickness: thickness,
    );
  }

  /// Generates a clean baseline DSF for a 4-Way Cable Tray Cross
  static DsfDocument createBaselineCross({
    double widthMain = 100.0,
    double widthBranch = 100.0,
    double height = 50.0,
    double thickness = 1.5,
  }) {
    final armLead = 100.0;
    final x1 = -widthBranch / 2.0 - armLead;
    final x2 = -widthBranch / 2.0;
    final x3 = widthBranch / 2.0;
    final x4 = widthBranch / 2.0 + armLead;

    final y1 = -widthMain / 2.0 - armLead;
    final y2 = -widthMain / 2.0;
    final y3 = widthMain / 2.0;
    final y4 = widthMain / 2.0 + armLead;

    final contour = <CadPoint2D>[
      CadPoint2D(x1, y2),
      CadPoint2D(x2, y2),
      CadPoint2D(x2, y1),
      CadPoint2D(x3, y1),
      CadPoint2D(x3, y2),
      CadPoint2D(x4, y2),
      CadPoint2D(x4, y3),
      CadPoint2D(x3, y3),
      CadPoint2D(x3, y4),
      CadPoint2D(x2, y4),
      CadPoint2D(x2, y3),
      CadPoint2D(x1, y3),
    ];

    final bends = <FoldBendLine>[
      FoldBendLine(
        id: 'BEND_CROSS_WEST',
        p1: CadPoint2D(x2, y2),
        p2: CadPoint2D(x2, y3),
        targetAngleDeg: 90.0,
        radiusMm: thickness,
        direction: BendDirection.up,
      ),
      FoldBendLine(
        id: 'BEND_CROSS_EAST',
        p1: CadPoint2D(x3, y2),
        p2: CadPoint2D(x3, y3),
        targetAngleDeg: 90.0,
        radiusMm: thickness,
        direction: BendDirection.up,
      ),
      FoldBendLine(
        id: 'BEND_CROSS_NORTH',
        p1: CadPoint2D(x2, y3),
        p2: CadPoint2D(x3, y3),
        targetAngleDeg: 90.0,
        radiusMm: thickness,
        direction: BendDirection.up,
      ),
      FoldBendLine(
        id: 'BEND_CROSS_SOUTH',
        p1: CadPoint2D(x2, y2),
        p2: CadPoint2D(x3, y2),
        targetAngleDeg: 90.0,
        radiusMm: thickness,
        direction: BendDirection.up,
      ),
    ];

    final punches = <CncPunchPrimitive>[
      CncPunchPrimitive.obround(
        id: 'PUNCH_CROSS_W',
        center: CadPoint2D(x1 + 25.0, 0.0),
        widthMm: 30.0,
        lengthMm: 7.0,
      ),
      CncPunchPrimitive.obround(
        id: 'PUNCH_CROSS_E',
        center: CadPoint2D(x4 - 25.0, 0.0),
        widthMm: 30.0,
        lengthMm: 7.0,
      ),
      CncPunchPrimitive.obround(
        id: 'PUNCH_CROSS_N',
        center: CadPoint2D(0.0, y4 - 25.0),
        widthMm: 7.0,
        lengthMm: 30.0,
        rotationDeg: 90.0,
      ),
      CncPunchPrimitive.obround(
        id: 'PUNCH_CROSS_S',
        center: CadPoint2D(0.0, y1 + 25.0),
        widthMm: 7.0,
        lengthMm: 30.0,
        rotationDeg: 90.0,
      ),
    ];

    final decomposed = PlanarFaceDecomposer.decompose(
      outerContour: contour,
      bends: bends,
    );

    return DsfDocument(
      productType: 'Cable Tray Cross',
      itemName: 'Cross_${widthMain.toInt()}x${height.toInt()}x${widthBranch.toInt()}',
      material: SheetMetalMaterial(thicknessMm: thickness),
      outerContour: contour,
      bends: bends,
      punches: punches,
      faces: decomposed.faces,
      baseFaceId: decomposed.baseFaceId,
      metadata: {
        'appliedTemplate': 'tray_cross',
        'templateParameters': {
          'widthMain': widthMain,
          'widthBranch': widthBranch,
          'width': widthMain,
          'branchWidth': widthBranch,
          'height': height,
        },
      },
    );
  }

  /// Automatically generates the appropriate baseline DSF for any registered template definition
  static DsfDocument createBaselineForTemplate(TemplateParameterDefinition template) {
    switch (template.templateId) {
      case 'tray_tee':
        return createBaselineTee(
          width: template.baselineParameters['width'] ?? 100.0,
          branchWidth: template.baselineParameters['branchWidth'] ?? 100.0,
          height: template.baselineParameters['height'] ?? 50.0,
        );
      case 'tray_bend_90':
        return createBaselineBend90(
          width: template.baselineParameters['width'] ?? 100.0,
          height: template.baselineParameters['height'] ?? 50.0,
          radius: template.baselineParameters['radius'] ?? 100.0,
        );
      case 'tray_bend_45':
        return createBaselineBend90(
          width: template.baselineParameters['width'] ?? 100.0,
          height: template.baselineParameters['height'] ?? 50.0,
          radius: template.baselineParameters['radius'] ?? 100.0,
        );
      case 'tray_reducer':
        return createBaselineReducer(
          widthIn: template.baselineParameters['widthIn'] ?? 100.0,
          widthOut: template.baselineParameters['widthOut'] ?? 50.0,
          height: template.baselineParameters['height'] ?? 50.0,
          length: template.baselineParameters['length'] ?? 150.0,
        );
      case 'tray_cross':
        return createBaselineCross(
          widthMain: template.baselineParameters['widthMain'] ?? template.baselineParameters['width'] ?? 100.0,
          widthBranch: template.baselineParameters['widthBranch'] ?? template.baselineParameters['branchWidth'] ?? 100.0,
          height: template.baselineParameters['height'] ?? 50.0,
        );
      case 'tray_straight':
      default:
        return createBaselineStraight(
          width: template.baselineParameters['width'] ?? 100.0,
          height: template.baselineParameters['height'] ?? 50.0,
          length: template.baselineParameters['length'] ?? 1000.0,
        );
    }
  }
}
