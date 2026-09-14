// =============================================================================
// topological_zone_morpher.dart
//
// Topological Zone Morphing Engine for Sheet Metal Studio (Master Guide #36-#48, P19-P22).
// Enables single DXF templates to parametrically morph without distorting
// invariant corner relief miters, bend notches, or standard tooling hole clusters.
// =============================================================================

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
        return _morphTee(baselineDocument, template, targetParameters);
      case 'tray_bend_90':
        return _morphBend90(baselineDocument, template, targetParameters);
      case 'tray_bend_45':
        return _morphBend45(baselineDocument, template, targetParameters);
      case 'tray_reducer':
        return _morphReducer(baselineDocument, template, targetParameters);
      case 'tray_cross':
        return _morphCross(baselineDocument, template, targetParameters);
      case 'tray_straight':
        return _morphStraight(baselineDocument, template, targetParameters);
      default:
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
  // 3. Cable Tray 45Â° Flat Bend Morpher
  // ===========================================================================
  static DsfDocument _morphBend45(
    DsfDocument baseline,
    TemplateParameterDefinition template,
    Map<String, double> targetParams,
  ) {
    final origW = template.baselineParameters['width'] ?? 100.0;
    final origH = template.baselineParameters['height'] ?? 50.0;
    final newW = targetParams['width'] ?? origW;
    final newH = targetParams['height'] ?? origH;
    final dW = newW - origW;

    final bounds = _computeBounds(baseline.outerContour);
    final midX = (bounds.minX + bounds.maxX) / 2.0;

    CadPoint2D morphPoint(CadPoint2D pt) {
      double x = pt.x;
      double y = pt.y;
      if (x > midX) {
        // Shift angled 45Â° arm along vector (cos 45Â°, sin 45Â°)
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
        return createBaselineTee(
          width: template.baselineParameters['width'] ?? 100.0,
          branchWidth: template.baselineParameters['branchWidth'] ?? 100.0,
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
