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

    // 1. Overall Blank Dimension
    if (dimension.type == CadDimensionType.overall ||
        dimension.id == 'dim_blank_w' ||
        dimension.id == 'dim_blank_l') {
      return _driveBlankDimension(document, dimension, newValue);
    }

    // 2. Punch / Hole Dimension (Diameter, Radius, Slot Length/Width, Center Position)
    if (dimension.referenceAId != null) {
      final punchMatch = document.punches.where((p) => p.id == dimension.referenceAId).firstOrNull;
      if (punchMatch != null) {
        return _drivePunchDimension(document, dimension, punchMatch, newValue);
      }

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
}
