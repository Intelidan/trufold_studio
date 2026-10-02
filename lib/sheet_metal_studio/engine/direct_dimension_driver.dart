// =============================================================================
// direct_dimension_driver.dart
//
// Direct Dimension Driving Engine per Master Guide Step 7 (#20).
// Solves geometric modifications when a dimension value is edited directly
// (driving dimension). Modifies underlying outerContour, punches, bends, or
// parameters and recomputes document consistency.
// =============================================================================

import 'dart:math' as math;
import '../models/cad_dimension.dart';
import '../models/cad_primitives.dart';
import '../models/dsf_document.dart';
import '../models/cnc_punch_primitive.dart';
import '../models/fold_bend_line.dart';
import 'planar_face_decomposer.dart';
import 'associative_dimension_engine.dart';

class DirectDimensionDriveResult {
  final DsfDocument updatedDocument;
  final CadDimension updatedDimension;
  final bool success;
  final String? errorMessage;
  final List<String> modifiedEntityIds;

  const DirectDimensionDriveResult({
    required this.updatedDocument,
    required this.updatedDimension,
    required this.success,
    this.errorMessage,
    this.modifiedEntityIds = const [],
  });
}

class DirectDimensionDriver {
  /// Drives a dimension to a new target value by modifying the underlying CAD geometry
  static DirectDimensionDriveResult drive({
    required DsfDocument document,
    required CadDimension dimension,
    required double newValue,
  }) {
    if (newValue <= 0.0 && dimension.type != CadDimensionType.angular) {
      return DirectDimensionDriveResult(
        updatedDocument: document,
        updatedDimension: dimension,
        success: false,
        errorMessage: 'Dimension value must be positive ($newValue <= 0)',
      );
    }

    // Check if linked to a named parameter
    if (dimension.parameterId != null && dimension.parameterId!.isNotEmpty) {
      final paramName = dimension.parameterId!;
      final updatedParams = Map<String, double>.from(document.parameters);
      updatedParams[paramName] = newValue;
      
      final updatedDim = dimension.copyWith(
        measuredValue: newValue,
        isDriven: false,
      );

      final updatedDoc = document.copyWith(
        parameters: updatedParams,
        dimensions: document.dimensions.map((d) => d.id == dimension.id ? updatedDim : d).toList(),
      );

      return DirectDimensionDriveResult(
        updatedDocument: updatedDoc,
        updatedDimension: updatedDim,
        success: true,
        modifiedEntityIds: ['param:$paramName'],
      );
    }

    // Angular Dimension between two entities / lines
    if (dimension.type == CadDimensionType.angular) {
      return _driveAngularDimension(document, dimension, newValue);
    }

    // 1. Overall Blank Dimension
    if (dimension.type == CadDimensionType.overall ||
        dimension.id == 'dim_blank_w' ||
        dimension.id == 'dim_blank_l') {
      return _driveBlankDimension(document, dimension, newValue);
    }

    // 2. Punch / Hole Dimension (Diameter, Radius, Slot Length/Width, Center Position, Pitch, Setback)
    final punchA = document.punches.where((p) => p.id == dimension.referenceAId).firstOrNull;
    final punchB = document.punches.where((p) => p.id == dimension.referenceBId).firstOrNull;

    if (punchA != null && punchB != null) {
      return _drivePunchToPunchDimension(document, dimension, punchA, punchB, newValue);
    } else if (punchA != null) {
      if (dimension.type == CadDimensionType.holeToEdge) {
        final edgePt = dimension.pointB ?? dimension.pointA ?? punchA.center;
        return _drivePunchToEdgeDimension(document, dimension, punchA, edgePt, newValue);
      }
      return _drivePunchDimension(document, dimension, punchA, newValue);
    } else if (punchB != null) {
      if (dimension.type == CadDimensionType.holeToEdge) {
        final edgePt = dimension.pointA ?? dimension.pointB ?? punchB.center;
        return _drivePunchToEdgeDimension(document, dimension, punchB, edgePt, newValue);
      }
      return _drivePunchDimension(document, dimension, punchB, newValue);
    }

    if (dimension.referenceAId != null) {
      // Check Bend line
      final bendMatch = document.bends.where((b) => b.id == dimension.referenceAId).firstOrNull;
      if (bendMatch != null) {
        return _driveBendDimension(document, dimension, bendMatch, newValue);
      }
    }

    // 3. Cut Line Dimension
    if (dimension.referenceAId != null) {
      final cutLineIndex = document.cutLines.indexWhere((c) => c.id == dimension.referenceAId);
      if (cutLineIndex >= 0) {
        return _driveCutLineDimension(document, dimension, cutLineIndex, newValue);
      }
    }

    // 4. Point-to-Point / Generic Geometric Dimension
    if (dimension.pointA != null && dimension.pointB != null) {
      return _drivePointToPointDimension(document, dimension, newValue);
    }

    // Fallback: update dimension value directly
    final updatedDim = dimension.copyWith(measuredValue: newValue, isDriven: false);
    final updatedDims = document.dimensions.map((d) => d.id == dimension.id ? updatedDim : d).toList();
    return DirectDimensionDriveResult(
      updatedDocument: document.copyWith(dimensions: updatedDims),
      updatedDimension: updatedDim,
      success: true,
      modifiedEntityIds: [dimension.id],
    );
  }

  static DirectDimensionDriveResult _drivePunchToPunchDimension(
    DsfDocument doc,
    CadDimension dim,
    CncPunchPrimitive punchA,
    CncPunchPrimitive punchB,
    double newValue,
  ) {
    // Default to moving punchB unless drivenEntityId explicitly specifies punchA.id
    final isBDriven = dim.drivenEntityId != punchA.id;
    final refPunch = isBDriven ? punchA : punchB;
    final drivenPunch = isBDriven ? punchB : punchA;

    final dx = drivenPunch.center.x - refPunch.center.x;
    final dy = drivenPunch.center.y - refPunch.center.y;
    final currentDist = math.sqrt(dx * dx + dy * dy);

    CadPoint2D newDrivenCenter = drivenPunch.center;
    CadPoint2D delta = const CadPoint2D(0, 0);

    if (dim.type == CadDimensionType.horizontal) {
      final sign = dx >= 0 ? 1.0 : -1.0;
      newDrivenCenter = CadPoint2D(refPunch.center.x + sign * newValue, drivenPunch.center.y);
      delta = CadPoint2D(newDrivenCenter.x - drivenPunch.center.x, 0);
    } else if (dim.type == CadDimensionType.vertical) {
      final sign = dy >= 0 ? 1.0 : -1.0;
      newDrivenCenter = CadPoint2D(drivenPunch.center.x, refPunch.center.y + sign * newValue);
      delta = CadPoint2D(0, newDrivenCenter.y - drivenPunch.center.y);
    } else {
      if (currentDist > 1e-4) {
        final factor = newValue / currentDist;
        newDrivenCenter = CadPoint2D(
          refPunch.center.x + dx * factor,
          refPunch.center.y + dy * factor,
        );
        delta = CadPoint2D(
          newDrivenCenter.x - drivenPunch.center.x,
          newDrivenCenter.y - drivenPunch.center.y,
        );
      }
    }

    final updatedDrivenPunch = drivenPunch.copyWith(center: newDrivenCenter);
    var updatedPunches = doc.punches.map((p) => p.id == drivenPunch.id ? updatedDrivenPunch : p).toList();

    // Propagate motion along dependent punch chains
    if (delta.x.abs() > 1e-4 || delta.y.abs() > 1e-4) {
      updatedPunches = _propagatePunchMotion(updatedPunches, doc.dimensions, drivenPunch.id, delta);
    }

    final updatedDim = dim.copyWith(
      pointA: isBDriven ? refPunch.center : newDrivenCenter,
      pointB: isBDriven ? newDrivenCenter : refPunch.center,
      measuredValue: newValue,
      isDriven: false,
      isDriving: true,
    );
    final updatedDims = doc.dimensions.map((d) => d.id == dim.id ? updatedDim : d).toList();

    return DirectDimensionDriveResult(
      updatedDocument: doc.copyWith(punches: updatedPunches, dimensions: updatedDims),
      updatedDimension: updatedDim,
      success: true,
      modifiedEntityIds: [drivenPunch.id],
    );
  }

  static DirectDimensionDriveResult _drivePunchToEdgeDimension(
    DsfDocument doc,
    CadDimension dim,
    CncPunchPrimitive punch,
    CadPoint2D edgePoint,
    double newValue,
  ) {
    final edgeId = dim.referenceAId == punch.id ? dim.referenceBId : dim.referenceAId;
    CadPoint2D effectiveEdgePoint = edgePoint;
    final edgeSeg = AssociativeDimensionEngine.resolveEdgeSegment(edgeId, doc);
    if (edgeSeg != null) {
      effectiveEdgePoint = AssociativeDimensionEngine.projectPointToSegmentLine(punch.center, edgeSeg.$1, edgeSeg.$2);
    }

    final dx = punch.center.x - effectiveEdgePoint.x;
    final dy = punch.center.y - effectiveEdgePoint.y;
    final currentDist = math.sqrt(dx * dx + dy * dy);

    CadPoint2D newPunchCenter = punch.center;
    CadPoint2D delta = const CadPoint2D(0, 0);

    if (currentDist > 1e-4) {
      final factor = newValue / currentDist;
      newPunchCenter = CadPoint2D(
        effectiveEdgePoint.x + dx * factor,
        effectiveEdgePoint.y + dy * factor,
      );
      delta = CadPoint2D(
        newPunchCenter.x - punch.center.x,
        newPunchCenter.y - punch.center.y,
      );
    }

    final updatedPunch = punch.copyWith(center: newPunchCenter);
    var updatedPunches = doc.punches.map((p) => p.id == punch.id ? updatedPunch : p).toList();

    // Propagate motion along dependent punch chains
    if (delta.x.abs() > 1e-4 || delta.y.abs() > 1e-4) {
      updatedPunches = _propagatePunchMotion(updatedPunches, doc.dimensions, punch.id, delta);
    }

    final updatedDim = dim.copyWith(
      pointA: dim.referenceAId == punch.id ? newPunchCenter : effectiveEdgePoint,
      pointB: dim.referenceAId == punch.id ? effectiveEdgePoint : newPunchCenter,
      measuredValue: newValue,
      isDriven: false,
      isDriving: true,
    );
    final updatedDims = doc.dimensions.map((d) => d.id == dim.id ? updatedDim : d).toList();

    return DirectDimensionDriveResult(
      updatedDocument: doc.copyWith(punches: updatedPunches, dimensions: updatedDims),
      updatedDimension: updatedDim,
      success: true,
      modifiedEntityIds: [punch.id],
    );
  }

  static List<CncPunchPrimitive> _propagatePunchMotion(
    List<CncPunchPrimitive> punches,
    List<CadDimension> dimensions,
    String movedPunchId,
    CadPoint2D delta,
  ) {
    if (delta.x.abs() < 1e-4 && delta.y.abs() < 1e-4) return punches;
    final movedPunchIds = <String>{movedPunchId};
    final queue = <String>[movedPunchId];
    final updatedPunches = {for (final p in punches) p.id: p};

    while (queue.isNotEmpty) {
      final currentId = queue.removeAt(0);
      for (final d in dimensions) {
        if (!d.isDriving) continue;
        if (d.type == CadDimensionType.holeToHole || d.type == CadDimensionType.centerToCenter) {
          final childId = (d.referenceAId == currentId)
              ? d.referenceBId
              : (d.referenceEntityId == currentId ? d.drivenEntityId : null);
          if (childId != null && !movedPunchIds.contains(childId) && updatedPunches.containsKey(childId)) {
            final childPunch = updatedPunches[childId]!;
            final newCenter = CadPoint2D(childPunch.center.x + delta.x, childPunch.center.y + delta.y);
            updatedPunches[childId] = childPunch.copyWith(center: newCenter);
            movedPunchIds.add(childId);
            queue.add(childId);
          }
        }
      }
    }

    return punches.map((p) => updatedPunches[p.id] ?? p).toList();
  }

  static DirectDimensionDriveResult _driveBlankDimension(
    DsfDocument doc,
    CadDimension dim,
    double newValue,
  ) {
    final isWidth = dim.id == 'dim_blank_w' || dim.type == CadDimensionType.horizontal || dim.type == CadDimensionType.overall;
    final currentW = doc.blankWidthMm;
    final currentL = doc.blankLengthMm;

    if (isWidth && currentW <= 0.0) return DirectDimensionDriveResult(updatedDocument: doc, updatedDimension: dim, success: false, errorMessage: 'Invalid blank width');
    if (!isWidth && currentL <= 0.0) return DirectDimensionDriveResult(updatedDocument: doc, updatedDimension: dim, success: false, errorMessage: 'Invalid blank length');

    final scaleX = isWidth ? (newValue / currentW) : 1.0;
    final scaleY = !isWidth ? (newValue / currentL) : 1.0;

    // Scale outer contour vertices
    final newContour = doc.outerContour.map((pt) {
      return CadPoint2D(pt.x * scaleX, pt.y * scaleY);
    }).toList();

    // Re-scale bends proportionally if scaling along their perpendicular
    final newBends = doc.bends.map((b) {
      return b.copyWith(
        p1: CadPoint2D(b.p1.x * scaleX, b.p1.y * scaleY),
        p2: CadPoint2D(b.p2.x * scaleX, b.p2.y * scaleY),
      );
    }).toList();

    // Recompute planar faces
    final decomp = PlanarFaceDecomposer.decompose(
      outerContour: newContour,
      bends: newBends,
    );

    final updatedDim = dim.copyWith(measuredValue: newValue, isDriven: false);
    final updatedDims = doc.dimensions.map((d) => d.id == dim.id ? updatedDim : d).toList();

    final updatedDoc = doc.copyWith(
      outerContour: newContour,
      bends: newBends,
      faces: decomp.faces,
      dimensions: updatedDims,
    );

    return DirectDimensionDriveResult(
      updatedDocument: updatedDoc,
      updatedDimension: updatedDim,
      success: true,
      modifiedEntityIds: ['outerContour', ...newBends.map((b) => b.id)],
    );
  }

  static DirectDimensionDriveResult _drivePunchDimension(
    DsfDocument doc,
    CadDimension dim,
    CncPunchPrimitive punch,
    double newValue,
  ) {
    CncPunchPrimitive updatedPunch = punch;
    if (dim.type == CadDimensionType.diameter) {
      updatedPunch = punch.copyWith(diameterMm: newValue);
    } else if (dim.type == CadDimensionType.radius) {
      updatedPunch = punch.copyWith(diameterMm: newValue * 2.0);
    } else if (dim.type == CadDimensionType.horizontal) {
      if (punch.type == PunchType.obroundSlot || punch.type == PunchType.rectangle) {
        updatedPunch = punch.copyWith(lengthMm: newValue);
      } else {
        updatedPunch = punch.copyWith(diameterMm: newValue);
      }
    } else if (dim.type == CadDimensionType.vertical) {
      if (punch.type == PunchType.obroundSlot || punch.type == PunchType.rectangle) {
        updatedPunch = punch.copyWith(widthMm: newValue);
      } else {
        updatedPunch = punch.copyWith(diameterMm: newValue);
      }
    } else if (dim.type == CadDimensionType.holeToEdge || dim.type == CadDimensionType.centerToCenter) {
      // Shift punch center
      if (dim.pointB != null) {
        final currentDist = math.sqrt(math.pow(punch.center.x - dim.pointB!.x, 2) + math.pow(punch.center.y - dim.pointB!.y, 2));
        if (currentDist > 1e-4) {
          final factor = newValue / currentDist;
          final newX = dim.pointB!.x + (punch.center.x - dim.pointB!.x) * factor;
          final newY = dim.pointB!.y + (punch.center.y - dim.pointB!.y) * factor;
          updatedPunch = punch.copyWith(center: CadPoint2D(newX, newY));
        }
      }
    }

    final newPunches = doc.punches.map((p) => p.id == punch.id ? updatedPunch : p).toList();
    final updatedDim = dim.copyWith(measuredValue: newValue, isDriven: false);
    final updatedDims = doc.dimensions.map((d) => d.id == dim.id ? updatedDim : d).toList();

    final updatedDoc = doc.copyWith(
      punches: newPunches,
      dimensions: updatedDims,
    );

    return DirectDimensionDriveResult(
      updatedDocument: updatedDoc,
      updatedDimension: updatedDim,
      success: true,
      modifiedEntityIds: [punch.id],
    );
  }

  static DirectDimensionDriveResult _driveBendDimension(
    DsfDocument doc,
    CadDimension dim,
    FoldBendLine bend,
    double newValue,
  ) {
    FoldBendLine updatedBend = bend;
    if (dim.type == CadDimensionType.angular) {
      updatedBend = bend.copyWith(targetAngleDeg: newValue);
    } else if (dim.type == CadDimensionType.radius) {
      updatedBend = bend.copyWith(radiusMm: newValue);
    } else if (dim.type == CadDimensionType.horizontal || dim.type == CadDimensionType.bendToEdge) {
      // Shift bend line along X
      final currentX = (bend.p1.x + bend.p2.x) / 2.0;
      final dx = newValue - currentX;
      updatedBend = bend.copyWith(
        p1: CadPoint2D(bend.p1.x + dx, bend.p1.y),
        p2: CadPoint2D(bend.p2.x + dx, bend.p2.y),
      );
    } else if (dim.type == CadDimensionType.vertical) {
      final currentY = (bend.p1.y + bend.p2.y) / 2.0;
      final dy = newValue - currentY;
      updatedBend = bend.copyWith(
        p1: CadPoint2D(bend.p1.x, bend.p1.y + dy),
        p2: CadPoint2D(bend.p2.x, bend.p2.y + dy),
      );
    }

    final newBends = doc.bends.map((b) => b.id == bend.id ? updatedBend : b).toList();
    final decomp = PlanarFaceDecomposer.decompose(
      outerContour: doc.outerContour,
      bends: newBends,
    );

    final updatedDim = dim.copyWith(measuredValue: newValue, isDriven: false);
    final updatedDims = doc.dimensions.map((d) => d.id == dim.id ? updatedDim : d).toList();

    final updatedDoc = doc.copyWith(
      bends: newBends,
      faces: decomp.faces,
      dimensions: updatedDims,
    );

    return DirectDimensionDriveResult(
      updatedDocument: updatedDoc,
      updatedDimension: updatedDim,
      success: true,
      modifiedEntityIds: [bend.id],
    );
  }

  static DirectDimensionDriveResult _driveCutLineDimension(
    DsfDocument doc,
    CadDimension dim,
    int cutLineIndex,
    double newValue,
  ) {
    final line = doc.cutLines[cutLineIndex];
    final dx = line.x2 - line.x1;
    final dy = line.y2 - line.y1;
    final currentLen = math.sqrt(dx * dx + dy * dy);

    CadLineSegment updatedLine = line;
    if (currentLen > 1e-4) {
      final factor = newValue / currentLen;
      updatedLine = line.copyWith(
        p2: CadPoint2D(line.p1.x + dx * factor, line.p1.y + dy * factor),
      );
    }

    final newLines = List<CadLineSegment>.from(doc.cutLines);
    newLines[cutLineIndex] = updatedLine;

    final updatedDim = dim.copyWith(measuredValue: newValue, isDriven: false);
    final updatedDims = doc.dimensions.map((d) => d.id == dim.id ? updatedDim : d).toList();

    final updatedDoc = doc.copyWith(
      cutLines: newLines,
      dimensions: updatedDims,
    );

    return DirectDimensionDriveResult(
      updatedDocument: updatedDoc,
      updatedDimension: updatedDim,
      success: true,
      modifiedEntityIds: [line.id],
    );
  }

  static DirectDimensionDriveResult _drivePointToPointDimension(
    DsfDocument doc,
    CadDimension dim,
    double newValue,
  ) {
    final pA = dim.pointA!;
    final pB = dim.pointB!;
    final dx = pB.x - pA.x;
    final dy = pB.y - pA.y;
    final currentDist = math.sqrt(dx * dx + dy * dy);

    CadPoint2D newB = pB;
    if (currentDist > 1e-4) {
      final factor = newValue / currentDist;
      newB = CadPoint2D(pA.x + dx * factor, pA.y + dy * factor);
    }

    final updatedDim = dim.copyWith(
      pointB: newB,
      measuredValue: newValue,
      isDriven: false,
    );

    final updatedDims = doc.dimensions.map((d) => d.id == dim.id ? updatedDim : d).toList();
    final updatedDoc = doc.copyWith(dimensions: updatedDims);

    return DirectDimensionDriveResult(
      updatedDocument: updatedDoc,
      updatedDimension: updatedDim,
      success: true,
      modifiedEntityIds: [dim.id],
    );
  }

  static CadPoint2D? _intersectLines(CadPoint2D a1, CadPoint2D a2, CadPoint2D b1, CadPoint2D b2) {
    final dxA = a2.x - a1.x;
    final dyA = a2.y - a1.y;
    final dxB = b2.x - b1.x;
    final dyB = b2.y - b1.y;
    final denom = dxA * dyB - dyA * dxB;
    if (denom.abs() < 1e-9) return null;
    final t = ((b1.x - a1.x) * dyB - (b1.y - a1.y) * dxB) / denom;
    return CadPoint2D(a1.x + t * dxA, a1.y + t * dyA);
  }

  static DirectDimensionDriveResult _driveAngularDimension(
    DsfDocument doc,
    CadDimension dim,
    double newAngleDeg,
  ) {
    final refA = dim.referenceAId;
    final refB = dim.referenceBId;

    final segA = AssociativeDimensionEngine.resolveEdgeSegment(refA, doc);
    final segB = AssociativeDimensionEngine.resolveEdgeSegment(refB, doc);

    if (segA != null && segB != null) {
      final pA1 = segA.$1;
      final pA2 = segA.$2;
      final pB1 = segB.$1;
      final pB2 = segB.$2;

      CadPoint2D pivot;
      CadPoint2D movingPt;
      bool pB1IsPivot = true;

      if (pB1.distanceTo(pA1) < 2.0 || pB1.distanceTo(pA2) < 2.0) {
        pivot = pB1;
        movingPt = pB2;
        pB1IsPivot = true;
      } else if (pB2.distanceTo(pA1) < 2.0 || pB2.distanceTo(pA2) < 2.0) {
        pivot = pB2;
        movingPt = pB1;
        pB1IsPivot = false;
      } else {
        final inter = _intersectLines(pA1, pA2, pB1, pB2);
        if (inter != null && inter.distanceTo(pB1) < 2000.0) {
          pivot = inter;
          movingPt = pB2;
          pB1IsPivot = false;
        } else {
          pivot = pB1;
          movingPt = pB2;
          pB1IsPivot = true;
        }
      }

      final thetaA = math.atan2(pA2.y - pA1.y, pA2.x - pA1.x);
      final currentThetaB = math.atan2(movingPt.y - pivot.y, movingPt.x - pivot.x);
      final currentDelta = currentThetaB - thetaA;
      final sign = (math.sin(currentDelta) >= 0) ? 1.0 : -1.0;
      final targetThetaB = thetaA + sign * (newAngleDeg * math.pi / 180.0);
      final armLen = pivot.distanceTo(movingPt);
      final effectiveLen = armLen > 0.1 ? armLen : pB1.distanceTo(pB2);

      final newMovingPt = CadPoint2D(
        pivot.x + effectiveLen * math.cos(targetThetaB),
        pivot.y + effectiveLen * math.sin(targetThetaB),
      );

      final newPB1 = pB1IsPivot ? pivot : newMovingPt;
      final newPB2 = pB1IsPivot ? newMovingPt : pivot;

      var updatedDoc = doc;
      String modifiedId = refB ?? '';

      if (refB != null && doc.cutLines.any((c) => c.id == refB)) {
        updatedDoc = updatedDoc.copyWith(
          cutLines: doc.cutLines.map((c) => c.id == refB ? c.copyWith(p1: newPB1, p2: newPB2) : c).toList(),
        );
      } else if (refB != null && doc.bends.any((b) => b.id == refB)) {
        updatedDoc = updatedDoc.copyWith(
          bends: doc.bends.map((b) => b.id == refB ? b.copyWith(p1: newPB1, p2: newPB2) : b).toList(),
        );
      } else if (refB != null && doc.dimensions.any((d) => d.id == refB)) {
        updatedDoc = updatedDoc.copyWith(
          dimensions: doc.dimensions.map((d) => d.id == refB ? d.copyWith(pointA: newPB1, pointB: newPB2) : d).toList(),
        );
      }

      final decomp = PlanarFaceDecomposer.decompose(
        outerContour: updatedDoc.outerContour,
        bends: updatedDoc.bends,
        cutLines: updatedDoc.cutLines,
      );

      final updatedDim = dim.copyWith(
        measuredValue: newAngleDeg,
        isDriven: false,
      );

      final updatedDims = updatedDoc.dimensions.map((d) => d.id == dim.id ? updatedDim : d).toList();

      return DirectDimensionDriveResult(
        updatedDocument: updatedDoc.copyWith(
          faces: decomp.faces,
          dimensions: updatedDims,
        ),
        updatedDimension: updatedDim,
        success: true,
        modifiedEntityIds: [modifiedId],
      );
    }

    final bendMatch = doc.bends.where((b) => b.id == refA).firstOrNull;
    if (bendMatch != null) {
      return _driveBendDimension(doc, dim, bendMatch, newAngleDeg);
    }

    final updatedDim = dim.copyWith(measuredValue: newAngleDeg, isDriven: false);
    return DirectDimensionDriveResult(
      updatedDocument: doc.copyWith(
        dimensions: doc.dimensions.map((d) => d.id == dim.id ? updatedDim : d).toList(),
      ),
      updatedDimension: updatedDim,
      success: true,
      modifiedEntityIds: [dim.id],
    );
  }
}
