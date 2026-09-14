// =============================================================================
// studio_command_delta.dart
//
// Memory-efficient Command/Delta action model for Trufold Sheet Metal Studio.
// Storing discrete deltas instead of full document clones prevents memory bloat
// across hundreds of undo steps, while recording a persistent featureHistory
// audit log embedded in .dsf files.
// =============================================================================

import 'package:flutter/foundation.dart';
import 'cad_primitives.dart';
import 'cnc_punch_primitive.dart';
import 'fold_bend_line.dart';
import 'planar_sheet_face.dart';
import 'perforation_pattern.dart';
import 'corner_treatment.dart';
import 'cad_dimension.dart';
import 'cad_constraint.dart';
import 'sheet_metal_material.dart';
import 'dsf_document.dart';

class StudioCommandDelta {
  final String description;
  final String actionType;
  final String? targetId;
  final DateTime timestamp;
  final Map<String, dynamic> params;

  // Delta payloads: only non-null for collections that actually mutated
  final List<CncPunchPrimitive>? oldPunches;
  final List<CncPunchPrimitive>? newPunches;
  final List<FoldBendLine>? oldBends;
  final List<FoldBendLine>? newBends;
  final List<PlanarSheetFace>? oldFaces;
  final List<PlanarSheetFace>? newFaces;
  final List<PerforationPattern>? oldPatterns;
  final List<PerforationPattern>? newPatterns;
  final List<CadPoint2D>? oldOuterContour;
  final List<CadPoint2D>? newOuterContour;
  final List<CadLineSegment>? oldCutLines;
  final List<CadLineSegment>? newCutLines;
  final List<CadDimension>? oldDimensions;
  final List<CadDimension>? newDimensions;
  final List<CadConstraint>? oldConstraints;
  final List<CadConstraint>? newConstraints;
  final List<CornerTreatment>? oldCorners;
  final List<CornerTreatment>? newCorners;
  final Map<String, double>? oldEdgeChamfers;
  final Map<String, double>? newEdgeChamfers;
  final Map<String, double>? oldParameters;
  final Map<String, double>? newParameters;
  final SheetMetalMaterial? oldMaterial;
  final SheetMetalMaterial? newMaterial;
  final String? oldBaseFaceId;
  final String? newBaseFaceId;
  final String? oldItemName;
  final String? newItemName;
  final String? oldProductType;
  final String? newProductType;

  StudioCommandDelta({
    required this.description,
    required this.actionType,
    this.targetId,
    DateTime? timestamp,
    this.params = const {},
    this.oldPunches,
    this.newPunches,
    this.oldBends,
    this.newBends,
    this.oldFaces,
    this.newFaces,
    this.oldPatterns,
    this.newPatterns,
    this.oldOuterContour,
    this.newOuterContour,
    this.oldCutLines,
    this.newCutLines,
    this.oldDimensions,
    this.newDimensions,
    this.oldConstraints,
    this.newConstraints,
    this.oldCorners,
    this.newCorners,
    this.oldEdgeChamfers,
    this.newEdgeChamfers,
    this.oldParameters,
    this.newParameters,
    this.oldMaterial,
    this.newMaterial,
    this.oldBaseFaceId,
    this.newBaseFaceId,
    this.oldItemName,
    this.newItemName,
    this.oldProductType,
    this.newProductType,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Creates a delta between two document states, storing ONLY the mutated collections.
  factory StudioCommandDelta.between(
    DsfDocument oldDoc,
    DsfDocument newDoc, {
    String? description,
    String? actionType,
    String? targetId,
    Map<String, dynamic>? params,
  }) {
    final punchesChanged = !identical(oldDoc.punches, newDoc.punches) &&
        !listEquals(oldDoc.punches, newDoc.punches);
    final bendsChanged = !identical(oldDoc.bends, newDoc.bends) &&
        !listEquals(oldDoc.bends, newDoc.bends);
    final facesChanged = !identical(oldDoc.faces, newDoc.faces) &&
        !listEquals(oldDoc.faces, newDoc.faces);
    final patternsChanged = !identical(oldDoc.perforationPatterns, newDoc.perforationPatterns) &&
        !listEquals(oldDoc.perforationPatterns, newDoc.perforationPatterns);
    final outerContourChanged = !identical(oldDoc.outerContour, newDoc.outerContour) &&
        !listEquals(oldDoc.outerContour, newDoc.outerContour);
    final cutLinesChanged = !identical(oldDoc.cutLines, newDoc.cutLines) &&
        !listEquals(oldDoc.cutLines, newDoc.cutLines);
    final dimensionsChanged = !identical(oldDoc.dimensions, newDoc.dimensions) &&
        !listEquals(oldDoc.dimensions, newDoc.dimensions);
    final constraintsChanged = !identical(oldDoc.constraints, newDoc.constraints) &&
        !listEquals(oldDoc.constraints, newDoc.constraints);
    final cornersChanged = !identical(oldDoc.corners, newDoc.corners) &&
        !listEquals(oldDoc.corners, newDoc.corners);
    final edgeChamfersChanged = !identical(oldDoc.edgeChamfers, newDoc.edgeChamfers) &&
        !mapEquals(oldDoc.edgeChamfers, newDoc.edgeChamfers);
    final parametersChanged = !identical(oldDoc.parameters, newDoc.parameters) &&
        !mapEquals(oldDoc.parameters, newDoc.parameters);
    final materialChanged = oldDoc.material != newDoc.material;
    final baseFaceIdChanged = oldDoc.baseFaceId != newDoc.baseFaceId;
    final itemNameChanged = oldDoc.itemName != newDoc.itemName;
    final productTypeChanged = oldDoc.productType != newDoc.productType;

    // Infer action type, targetId, and description if not provided
    String inferredAction = actionType ?? 'modify';
    String? inferredTargetId = targetId;
    String inferredDescription = description ?? 'Model Modification';

    if (outerContourChanged || parametersChanged) {
      inferredAction = actionType ?? 'drive_dimension';
      inferredDescription = description ?? 'Drive blank dimension / contour';
    } else if (punchesChanged) {
      if (newDoc.punches.length > oldDoc.punches.length) {
        final added = newDoc.punches.last;
        inferredAction = actionType ?? 'add_punch';
        inferredTargetId ??= added.id;
        inferredDescription = description ?? 'Add ${added.type.name} punch (${added.id})';
      } else if (newDoc.punches.length < oldDoc.punches.length) {
        final removed = oldDoc.punches.firstWhere(
          (p) => !newDoc.punches.any((np) => np.id == p.id),
          orElse: () => oldDoc.punches.last,
        );
        inferredAction = actionType ?? 'delete_punch';
        inferredTargetId ??= removed.id;
        inferredDescription = description ?? 'Delete punch (${removed.id})';
      } else {
        final changed = newDoc.punches.firstWhere(
          (np) => oldDoc.punches.any((op) => op.id == np.id && op != np),
          orElse: () => newDoc.punches.first,
        );
        inferredAction = actionType ?? 'update_punch';
        inferredTargetId ??= changed.id;
        inferredDescription = description ?? 'Update punch (${changed.id})';
      }
    } else if (bendsChanged) {
      if (newDoc.bends.length > oldDoc.bends.length) {
        final added = newDoc.bends.last;
        inferredAction = actionType ?? 'add_bend';
        inferredTargetId ??= added.id;
        inferredDescription = description ?? 'Add bend line (${added.id})';
      } else if (newDoc.bends.length < oldDoc.bends.length) {
        final removed = oldDoc.bends.firstWhere(
          (b) => !newDoc.bends.any((nb) => nb.id == b.id),
          orElse: () => oldDoc.bends.last,
        );
        inferredAction = actionType ?? 'delete_bend';
        inferredTargetId ??= removed.id;
        inferredDescription = description ?? 'Delete bend line (${removed.id})';
      } else {
        final changed = newDoc.bends.firstWhere(
          (nb) => oldDoc.bends.any((ob) => ob.id == nb.id && ob != nb),
          orElse: () => newDoc.bends.first,
        );
        inferredAction = actionType ?? 'update_bend';
        inferredTargetId ??= changed.id;
        inferredDescription = description ?? 'Update bend (${changed.id})';
      }
    } else if (patternsChanged) {
      if (newDoc.perforationPatterns.length > oldDoc.perforationPatterns.length) {
        final added = newDoc.perforationPatterns.last;
        inferredAction = actionType ?? 'add_pattern';
        inferredTargetId ??= added.id;
        inferredDescription = description ?? 'Apply perforation pattern (${added.id})';
      } else if (newDoc.perforationPatterns.length < oldDoc.perforationPatterns.length) {
        final removed = oldDoc.perforationPatterns.firstWhere(
          (p) => !newDoc.perforationPatterns.any((np) => np.id == p.id),
          orElse: () => oldDoc.perforationPatterns.last,
        );
        inferredAction = actionType ?? 'delete_pattern';
        inferredTargetId ??= removed.id;
        inferredDescription = description ?? 'Delete perforation pattern (${removed.id})';
      } else {
        final changed = newDoc.perforationPatterns.firstWhere(
          (np) => oldDoc.perforationPatterns.any((op) => op.id == np.id && op != np),
          orElse: () => newDoc.perforationPatterns.first,
        );
        inferredAction = actionType ?? 'update_pattern';
        inferredTargetId ??= changed.id;
        inferredDescription = description ?? 'Update perforation pattern (${changed.id})';
      }
    } else if (edgeChamfersChanged) {
      inferredAction = actionType ?? 'update_chamfer';
      inferredDescription = description ?? 'Update edge chamfer';
    } else if (dimensionsChanged) {
      inferredAction = actionType ?? 'update_dimension';
      inferredDescription = description ?? 'Update CAD dimensions';
    } else if (facesChanged) {
      inferredAction = actionType ?? 'update_faces';
      inferredDescription = description ?? 'Update planar sheet faces';
    }

    return StudioCommandDelta(
      description: inferredDescription,
      actionType: inferredAction,
      targetId: inferredTargetId,
      params: params ?? const {},
      oldPunches: punchesChanged ? oldDoc.punches : null,
      newPunches: punchesChanged ? newDoc.punches : null,
      oldBends: bendsChanged ? oldDoc.bends : null,
      newBends: bendsChanged ? newDoc.bends : null,
      oldFaces: facesChanged ? oldDoc.faces : null,
      newFaces: facesChanged ? newDoc.faces : null,
      oldPatterns: patternsChanged ? oldDoc.perforationPatterns : null,
      newPatterns: patternsChanged ? newDoc.perforationPatterns : null,
      oldOuterContour: outerContourChanged ? oldDoc.outerContour : null,
      newOuterContour: outerContourChanged ? newDoc.outerContour : null,
      oldCutLines: cutLinesChanged ? oldDoc.cutLines : null,
      newCutLines: cutLinesChanged ? newDoc.cutLines : null,
      oldDimensions: dimensionsChanged ? oldDoc.dimensions : null,
      newDimensions: dimensionsChanged ? newDoc.dimensions : null,
      oldConstraints: constraintsChanged ? oldDoc.constraints : null,
      newConstraints: constraintsChanged ? newDoc.constraints : null,
      oldCorners: cornersChanged ? oldDoc.corners : null,
      newCorners: cornersChanged ? newDoc.corners : null,
      oldEdgeChamfers: edgeChamfersChanged ? oldDoc.edgeChamfers : null,
      newEdgeChamfers: edgeChamfersChanged ? newDoc.edgeChamfers : null,
      oldParameters: parametersChanged ? oldDoc.parameters : null,
      newParameters: parametersChanged ? newDoc.parameters : null,
      oldMaterial: materialChanged ? oldDoc.material : null,
      newMaterial: materialChanged ? newDoc.material : null,
      oldBaseFaceId: baseFaceIdChanged ? oldDoc.baseFaceId : null,
      newBaseFaceId: baseFaceIdChanged ? newDoc.baseFaceId : null,
      oldItemName: itemNameChanged ? oldDoc.itemName : null,
      newItemName: itemNameChanged ? newDoc.itemName : null,
      oldProductType: productTypeChanged ? oldDoc.productType : null,
      newProductType: productTypeChanged ? newDoc.productType : null,
    );
  }

  /// Reverts the document to its previous state
  DsfDocument undo(DsfDocument current) {
    // If explicit snapshots exist, restore directly
    if (oldPunches != null ||
        oldBends != null ||
        oldFaces != null ||
        oldPatterns != null ||
        oldOuterContour != null ||
        oldCutLines != null ||
        oldDimensions != null ||
        oldConstraints != null ||
        oldCorners != null ||
        oldEdgeChamfers != null ||
        oldParameters != null ||
        oldMaterial != null ||
        oldBaseFaceId != null ||
        oldItemName != null ||
        oldProductType != null) {
      return current.copyWith(
        punches: oldPunches ?? current.punches,
        bends: oldBends ?? current.bends,
        faces: oldFaces ?? current.faces,
        perforationPatterns: oldPatterns ?? current.perforationPatterns,
        outerContour: oldOuterContour ?? current.outerContour,
        cutLines: oldCutLines ?? current.cutLines,
        dimensions: oldDimensions ?? current.dimensions,
        constraints: oldConstraints ?? current.constraints,
        corners: oldCorners ?? current.corners,
        edgeChamfers: oldEdgeChamfers ?? current.edgeChamfers,
        parameters: oldParameters ?? current.parameters,
        material: oldMaterial ?? current.material,
        baseFaceId: oldBaseFaceId ?? current.baseFaceId,
        itemName: oldItemName ?? current.itemName,
        productType: oldProductType ?? current.productType,
      );
    }

    // Fallback for legacy history entries without explicit snapshots
    if (targetId != null) {
      if (actionType == 'add_punch') {
        return current.copyWith(
          punches: current.punches.where((p) => p.id != targetId).toList(),
        );
      }
      if (actionType == 'add_bend') {
        return current.copyWith(
          bends: current.bends.where((b) => b.id != targetId).toList(),
        );
      }
      if (actionType == 'add_pattern') {
        return current.copyWith(
          perforationPatterns: current.perforationPatterns
              .where((p) => p.id != targetId)
              .toList(),
        );
      }
    }

    return current;
  }

  /// Re-applies the document mutation
  DsfDocument redo(DsfDocument current) {
    return current.copyWith(
      punches: newPunches ?? current.punches,
      bends: newBends ?? current.bends,
      faces: newFaces ?? current.faces,
      perforationPatterns: newPatterns ?? current.perforationPatterns,
      outerContour: newOuterContour ?? current.outerContour,
      cutLines: newCutLines ?? current.cutLines,
      dimensions: newDimensions ?? current.dimensions,
      constraints: newConstraints ?? current.constraints,
      corners: newCorners ?? current.corners,
      edgeChamfers: newEdgeChamfers ?? current.edgeChamfers,
      parameters: newParameters ?? current.parameters,
      material: newMaterial ?? current.material,
      baseFaceId: newBaseFaceId ?? current.baseFaceId,
      itemName: newItemName ?? current.itemName,
      productType: newProductType ?? current.productType,
    );
  }

  /// Compact audit log record for DsfDocument.metadata['featureHistory']
  Map<String, dynamic> toFeatureHistoryEntry({int step = 1}) {
    return {
      'step': step,
      'action': actionType,
      'description': description,
      'timestamp': timestamp.toIso8601String(),
      if (targetId != null) 'targetId': targetId,
      if (params.isNotEmpty) 'params': params,
      'delta': toJson(),
    };
  }

  /// Serializes only the non-null mutated delta collections to JSON
  Map<String, dynamic> toJson() => {
    'description': description,
    'actionType': actionType,
    'timestamp': timestamp.toIso8601String(),
    if (targetId != null) 'targetId': targetId,
    if (params.isNotEmpty) 'params': params,
    if (oldPunches != null)
      'oldPunches': oldPunches!.map((p) => p.toJson()).toList(),
    if (newPunches != null)
      'newPunches': newPunches!.map((p) => p.toJson()).toList(),
    if (oldBends != null) 'oldBends': oldBends!.map((b) => b.toJson()).toList(),
    if (newBends != null) 'newBends': newBends!.map((b) => b.toJson()).toList(),
    if (oldFaces != null) 'oldFaces': oldFaces!.map((f) => f.toJson()).toList(),
    if (newFaces != null) 'newFaces': newFaces!.map((f) => f.toJson()).toList(),
    if (oldPatterns != null)
      'oldPatterns': oldPatterns!.map((p) => p.toJson()).toList(),
    if (newPatterns != null)
      'newPatterns': newPatterns!.map((p) => p.toJson()).toList(),
    if (oldOuterContour != null)
      'oldOuterContour': oldOuterContour!.map((p) => p.toJson()).toList(),
    if (newOuterContour != null)
      'newOuterContour': newOuterContour!.map((p) => p.toJson()).toList(),
    if (oldCutLines != null)
      'oldCutLines': oldCutLines!.map((c) => c.toJson()).toList(),
    if (newCutLines != null)
      'newCutLines': newCutLines!.map((c) => c.toJson()).toList(),
    if (oldDimensions != null)
      'oldDimensions': oldDimensions!.map((d) => d.toJson()).toList(),
    if (newDimensions != null)
      'newDimensions': newDimensions!.map((d) => d.toJson()).toList(),
    if (oldConstraints != null)
      'oldConstraints': oldConstraints!.map((c) => c.toJson()).toList(),
    if (newConstraints != null)
      'newConstraints': newConstraints!.map((c) => c.toJson()).toList(),
    if (oldCorners != null)
      'oldCorners': oldCorners!.map((c) => c.toJson()).toList(),
    if (newCorners != null)
      'newCorners': newCorners!.map((c) => c.toJson()).toList(),
    if (oldEdgeChamfers != null) 'oldEdgeChamfers': oldEdgeChamfers,
    if (newEdgeChamfers != null) 'newEdgeChamfers': newEdgeChamfers,
    if (oldParameters != null) 'oldParameters': oldParameters,
    if (newParameters != null) 'newParameters': newParameters,
    if (oldMaterial != null) 'oldMaterial': oldMaterial!.toJson(),
    if (newMaterial != null) 'newMaterial': newMaterial!.toJson(),
    if (oldBaseFaceId != null) 'oldBaseFaceId': oldBaseFaceId,
    if (newBaseFaceId != null) 'newBaseFaceId': newBaseFaceId,
    if (oldItemName != null) 'oldItemName': oldItemName,
    if (newItemName != null) 'newItemName': newItemName,
    if (oldProductType != null) 'oldProductType': oldProductType,
    if (newProductType != null) 'newProductType': newProductType,
  };

  /// Reconstructs a StudioCommandDelta from serialized JSON
  factory StudioCommandDelta.fromJson(Map<String, dynamic> json) {
    return StudioCommandDelta(
      description: json['description'] as String? ?? 'Command',
      actionType: json['actionType'] as String? ?? 'modify',
      targetId: json['targetId'] as String?,
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
      params: (json['params'] as Map<String, dynamic>?) ?? const {},
      oldPunches: (json['oldPunches'] as List?)
          ?.map((e) => CncPunchPrimitive.fromJson(e as Map<String, dynamic>))
          .toList(),
      newPunches: (json['newPunches'] as List?)
          ?.map((e) => CncPunchPrimitive.fromJson(e as Map<String, dynamic>))
          .toList(),
      oldBends: (json['oldBends'] as List?)
          ?.map((e) => FoldBendLine.fromJson(e as Map<String, dynamic>))
          .toList(),
      newBends: (json['newBends'] as List?)
          ?.map((e) => FoldBendLine.fromJson(e as Map<String, dynamic>))
          .toList(),
      oldFaces: (json['oldFaces'] as List?)
          ?.map((e) => PlanarSheetFace.fromJson(e as Map<String, dynamic>))
          .toList(),
      newFaces: (json['newFaces'] as List?)
          ?.map((e) => PlanarSheetFace.fromJson(e as Map<String, dynamic>))
          .toList(),
      oldPatterns: (json['oldPatterns'] as List?)
          ?.map((e) => PerforationPattern.fromJson(e as Map<String, dynamic>))
          .toList(),
      newPatterns: (json['newPatterns'] as List?)
          ?.map((e) => PerforationPattern.fromJson(e as Map<String, dynamic>))
          .toList(),
      oldOuterContour: (json['oldOuterContour'] as List?)
          ?.map((e) => CadPoint2D.fromJson(e as Map<String, dynamic>))
          .toList(),
      newOuterContour: (json['newOuterContour'] as List?)
          ?.map((e) => CadPoint2D.fromJson(e as Map<String, dynamic>))
          .toList(),
      oldCutLines: (json['oldCutLines'] as List?)
          ?.map((e) => CadLineSegment.fromJson(e as Map<String, dynamic>))
          .toList(),
      newCutLines: (json['newCutLines'] as List?)
          ?.map((e) => CadLineSegment.fromJson(e as Map<String, dynamic>))
          .toList(),
      oldDimensions: (json['oldDimensions'] as List?)
          ?.map((e) => CadDimension.fromJson(e as Map<String, dynamic>))
          .toList(),
      newDimensions: (json['newDimensions'] as List?)
          ?.map((e) => CadDimension.fromJson(e as Map<String, dynamic>))
          .toList(),
      oldConstraints: (json['oldConstraints'] as List?)
          ?.map((e) => CadConstraint.fromJson(e as Map<String, dynamic>))
          .toList(),
      newConstraints: (json['newConstraints'] as List?)
          ?.map((e) => CadConstraint.fromJson(e as Map<String, dynamic>))
          .toList(),
      oldCorners: (json['oldCorners'] as List?)
          ?.map((e) => CornerTreatment.fromJson(e as Map<String, dynamic>))
          .toList(),
      newCorners: (json['newCorners'] as List?)
          ?.map((e) => CornerTreatment.fromJson(e as Map<String, dynamic>))
          .toList(),
      oldEdgeChamfers: (json['oldEdgeChamfers'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, (v as num).toDouble())),
      newEdgeChamfers: (json['newEdgeChamfers'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, (v as num).toDouble())),
      oldParameters: (json['oldParameters'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, (v as num).toDouble())),
      newParameters: (json['newParameters'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, (v as num).toDouble())),
      oldMaterial: json['oldMaterial'] != null
          ? SheetMetalMaterial.fromJson(
              json['oldMaterial'] as Map<String, dynamic>,
            )
          : null,
      newMaterial: json['newMaterial'] != null
          ? SheetMetalMaterial.fromJson(
              json['newMaterial'] as Map<String, dynamic>,
            )
          : null,
      oldBaseFaceId: json['oldBaseFaceId'] as String?,
      newBaseFaceId: json['newBaseFaceId'] as String?,
      oldItemName: json['oldItemName'] as String?,
      newItemName: json['newItemName'] as String?,
      oldProductType: json['oldProductType'] as String?,
      newProductType: json['newProductType'] as String?,
    );
  }

  /// Reconstructs a StudioCommandDelta from a legacy featureHistory audit log entry
  factory StudioCommandDelta.fromLegacyHistoryEntry(
    Map<String, dynamic> entry,
  ) {
    final action = entry['action'] as String? ?? 'modify';
    final desc = entry['description'] as String? ?? 'Historical Action';
    final targetId = entry['targetId'] as String?;
    final timestamp = entry['timestamp'] != null
        ? DateTime.tryParse(entry['timestamp'] as String)
        : null;
    final params = (entry['params'] as Map<String, dynamic>?) ?? const {};

    return StudioCommandDelta(
      description: desc,
      actionType: action,
      targetId: targetId,
      timestamp: timestamp,
      params: params,
    );
  }
}
