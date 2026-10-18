// =============================================================================
// dam_file_service.dart
//
// File Service for TruFold Digital Assembly Model (.dam) format,
// multi-DSF importing, CMS accessory template loading, and inter-studio bridge.
// =============================================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' as vm_math;

import '../../../sheet_metal_studio/models/cad_primitives.dart';
import '../../../sheet_metal_studio/models/dsf_document.dart';
import '../../../sheet_metal_studio/engine/kinematic_fold_engine.dart';
import '../../../sheet_metal_studio/models/ladder/ladder_assembly_models.dart';
import '../../../sheet_metal_studio/services/studio_file_service.dart';
import '../../../sketch_draft_files/cad_parameter_engine/cad_models.dart';
import '../../models/assembly_part.dart';
import '../../models/assembly_timeline_item.dart';
import '../../models/dam_document.dart';
import '../../viewmodels/assembly_studio_viewmodel.dart';

class DamFileService {
  /// Serializes the entire active assembly session into a standard .dam JSON string.
  static String exportToDamJson(AssemblyStudioViewModel vm) {
    final doc = vm.doc;

    final partsData = doc.parts.map((p) {
      List<Map<String, dynamic>>? customPolysJson;
      if (p.customPolygons != null) {
        customPolysJson = p.customPolygons!.map((poly) {
          return {
            'faceId': poly.faceId,
            'normal': [poly.normal.x, poly.normal.y, poly.normal.z],
            'color': poly.color.toARGB32(),
            'vertices': poly.vertices.map((v) => [v.x, v.y, v.z]).toList(),
            'drawWireframe': poly.drawWireframe,
          };
        }).toList();
      }

      return DamPartData(
        id: p.id,
        name: p.name,
        typeName: p.type.name,
        posX: p.position.x,
        posY: p.position.y,
        posZ: p.position.z,
        rotX: p.rotationDeg.x,
        rotY: p.rotationDeg.y,
        rotZ: p.rotationDeg.z,
        length: p.length,
        height: p.height,
        flangeWidth: p.flangeWidth,
        thickness: p.thickness,
        isFlangeOutward: p.isFlangeOutward,
        colorValue: p.color.toARGB32(),
        isVisible: p.isVisible,
        parentPartId: p.parentPartId,
        matedSlotEntityId: p.matedSlotEntityId,
        mateStyle: p.mateStyle,
        weldedToPartIds: List.from(p.weldedToPartIds),
        sourceDsfJson: p.sourceDsfJson,
        customPolygonsJson: customPolysJson,
      );
    }).toList();

    final weldsData = doc.welds.map((w) {
      return DamWeldData(
        id: w.id,
        partAId: w.partAId,
        partBId: w.partBId,
        wx: w.weldPoint.x,
        wy: w.weldPoint.y,
        wz: w.weldPoint.z,
        ax: w.weldAxis.x,
        ay: w.weldAxis.y,
        az: w.weldAxis.z,
        weldLengthMm: w.weldLengthMm,
        weldSizeMm: w.weldSizeMm,
        bothSides: w.bothSides,
        sWx: w.secondWeldPoint?.x,
        sWy: w.secondWeldPoint?.y,
        sWz: w.secondWeldPoint?.z,
        jointDescription: w.jointDescription,
        jointTypeName: w.jointType.name,
        mateStyle: w.mateStyle,
      );
    }).toList();

    final planesData = vm.savedSketchPlanes.map((plane) {
      return DamSketchPlaneData(
        id: plane.id,
        name: plane.name,
        planeType: plane.planeType.name,
        ox: plane.origin.x,
        oy: plane.origin.y,
        oz: plane.origin.z,
        nx: plane.normal.x,
        ny: plane.normal.y,
        nz: plane.normal.z,
        ux: plane.xAxis.x,
        uy: plane.xAxis.y,
        uz: plane.xAxis.z,
        size: plane.size,
        targetPartId: plane.targetPartId,
        primitives: plane.primitives.map(_primitiveToJson).toList(),
        constraints: plane.constraints.map((c) => c.toJson()).toList(),
      );
    }).toList();

    final featureTreeData = doc.featureTree.map((item) {
      return DamFeatureTreeItemData(
        id: item.id,
        name: item.name,
        kind: item.kind.name,
        entityId: item.entityId,
        parentSketchId: item.parentSketchId,
        parameters: item.parameters,
        isSuppressed: item.isSuppressed,
      );
    }).toList();

    final dam = DamDocument(
      title: doc.title,
      systemType: 'Cable Management System',
      metadata: {'author': 'TruFold Studio', 'appVersion': '2.0.0'},
      parts: partsData,
      welds: weldsData,
      sketchPlanes: planesData,
      featureTree: featureTreeData,
    );

    return const JsonEncoder.withIndent('  ').convert(dam.toJson());
  }

  /// Deserializes a .dam JSON string and rebuilds the full assembly session.
  static bool importFromDamJson(String jsonStr, AssemblyStudioViewModel vm) {
    try {
      final jsonMap = jsonDecode(jsonStr) as Map<String, dynamic>;
      final dam = DamDocument.fromJson(jsonMap);

      vm.doc.title = dam.title;
      vm.doc.parts.clear();
      vm.doc.welds.clear();
      vm.doc.featureTree.clear();
      vm.timelineItems.clear();
      vm.savedSketchPlanes.clear();

      // 1. Reconstruct Parts
      for (final pData in dam.parts) {
        AssemblyPartType pType = AssemblyPartType.straightRail;
        for (final t in AssemblyPartType.values) {
          if (t.name == pData.typeName) {
            pType = t;
            break;
          }
        }

        List<CadFoldedPolygon3D>? customPolys;
        if (pData.customPolygonsJson != null) {
          customPolys = pData.customPolygonsJson!.map((pj) {
            final norm = (pj['normal'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList() ?? [0.0, 0.0, 1.0];
            final verts = (pj['vertices'] as List<dynamic>?)?.map((v) {
                  final vl = (v as List<dynamic>).map((e) => (e as num).toDouble()).toList();
                  return CadPoint3D(vl[0], vl[1], vl[2]);
                }).toList() ??
                <CadPoint3D>[];

            return CadFoldedPolygon3D(
              faceId: pj['faceId'] as String? ?? 'face_0',
              vertices: verts,
              normal: CadPoint3D(norm[0], norm[1], norm[2]),
              color: Color(pj['color'] as int? ?? 0xFF6C9DC6),
              drawWireframe: pj['drawWireframe'] as bool? ?? false,
            );
          }).toList();
        }

        final part = AssemblyPart(
          id: pData.id,
          name: pData.name,
          type: pType,
          position: CadPoint3D(pData.posX, pData.posY, pData.posZ),
          rotationDeg: CadPoint3D(pData.rotX, pData.rotY, pData.rotZ),
          length: pData.length,
          height: pData.height,
          flangeWidth: pData.flangeWidth,
          thickness: pData.thickness,
          isFlangeOutward: pData.isFlangeOutward,
          color: Color(pData.colorValue),
          isVisible: pData.isVisible,
          parentPartId: pData.parentPartId,
          matedSlotEntityId: pData.matedSlotEntityId,
          mateStyle: pData.mateStyle,
          weldedToPartIds: List.from(pData.weldedToPartIds),
          sourceDsfJson: pData.sourceDsfJson,
          customPolygons: customPolys,
        );

        vm.doc.parts.add(part);
      }

      // 2. Reconstruct Welds
      for (final wData in dam.welds) {
        AssemblyJointType jType = AssemblyJointType.welded;
        for (final jt in AssemblyJointType.values) {
          if (jt.name == wData.jointTypeName) {
            jType = jt;
            break;
          }
        }

        vm.doc.welds.add(
          AssemblyWeldJoint(
            id: wData.id,
            partAId: wData.partAId,
            partBId: wData.partBId,
            weldPoint: CadPoint3D(wData.wx, wData.wy, wData.wz),
            weldAxis: CadPoint3D(wData.ax, wData.ay, wData.az),
            weldLengthMm: wData.weldLengthMm,
            weldSizeMm: wData.weldSizeMm,
            bothSides: wData.bothSides,
            secondWeldPoint: wData.sWx != null ? CadPoint3D(wData.sWx!, wData.sWy!, wData.sWz!) : null,
            jointDescription: wData.jointDescription,
            jointType: jType,
            mateStyle: wData.mateStyle,
          ),
        );
      }

      // 3. Reconstruct Sketch Planes
      for (final spData in dam.sketchPlanes) {
        CADPlaneType planeType = CADPlaneType.facePlane;
        for (final pt in CADPlaneType.values) {
          if (pt.name == spData.planeType) {
            planeType = pt;
            break;
          }
        }

        final plane = CADSketchPlane(
          id: spData.id,
          name: spData.name,
          planeType: planeType,
          origin: vm_math.Vector3(spData.ox, spData.oy, spData.oz),
          normal: vm_math.Vector3(spData.nx, spData.ny, spData.nz),
          up: vm_math.Vector3(spData.ux, spData.uy, spData.uz),
          size: spData.size,
          targetPartId: spData.targetPartId,
        );

        for (final pj in spData.primitives) {
          final prim = _primitiveFromJson(pj);
          if (prim != null) plane.primitives.add(prim);
        }

        for (final cj in spData.constraints) {
          plane.constraints.add(CadConstraint.fromJson(cj));
        }

        vm.savedSketchPlanes.add(plane);
      }

      // 4. Reconstruct Feature Tree
      for (final ftData in dam.featureTree) {
        AssemblyFeatureKind kind = AssemblyFeatureKind.sketch;
        for (final k in AssemblyFeatureKind.values) {
          if (k.name == ftData.kind) {
            kind = k;
            break;
          }
        }

        vm.doc.featureTree.add(
          AssemblyTimelineItem(
            id: ftData.id,
            name: ftData.name,
            kind: kind,
            entityId: ftData.entityId,
            parentSketchId: ftData.parentSketchId,
            parameters: ftData.parameters,
            isSuppressed: ftData.isSuppressed,
          ),
        );
      }
      vm.timelineItems.addAll(vm.doc.featureTree);

      vm.invalidateMeshCache();
      vm.solveSketchConstraints();
      vm.notifyDocChanged();
      return true;
    } catch (e, st) {
      debugPrint('Error importing .dam file: $e\n$st');
      return false;
    }
  }

  /// Converts a single Sheet Metal [DsfDocument] into an [AssemblyPart] with 3D folded geometry.
  static AssemblyPart convertDsfToAssemblyPart({
    required DsfDocument dsfDoc,
    required String rawJsonStr,
    CadPoint3D position = const CadPoint3D(0.0, 0.0, 0.0),
    String? customId,
  }) {
    // 1. Fold 2D kinematics into 3D folded polygons
    final foldResult = KinematicFoldEngine.foldDocument(dsfDoc, foldProgress: 1.0);

    // 2. Classify CMS product type
    AssemblyPartType partType = AssemblyPartType.customSheetMetal;
    final lowerName = dsfDoc.itemName.toLowerCase();
    final lowerType = dsfDoc.productType.toLowerCase();

    if (lowerName.contains('bend') || lowerType.contains('bend')) {
      partType = lowerName.contains('tray') ? AssemblyPartType.cableTrayBend90 : AssemblyPartType.cableTrunkingBend;
    } else if (lowerName.contains('riser') || lowerType.contains('riser')) {
      partType = lowerName.contains('inside') ? AssemblyPartType.cableTrayInsideRiser : AssemblyPartType.cableTrayOutsideRiser;
    } else if (lowerName.contains('tee') || lowerType.contains('tee')) {
      partType = AssemblyPartType.cableTrayTee;
    } else if (lowerName.contains('cross') || lowerType.contains('cross')) {
      partType = AssemblyPartType.cableTrayCross;
    } else if (lowerName.contains('reducer') || lowerType.contains('reducer')) {
      partType = AssemblyPartType.cableTrayReducer;
    } else if (lowerName.contains('trunk') || lowerType.contains('trunk')) {
      partType = AssemblyPartType.cableTrunkingBody;
    } else if (lowerName.contains('tray') || lowerType.contains('tray')) {
      partType = AssemblyPartType.cableTrayStraight;
    }

    // 3. Construct 3D Assembly Part
    final id = customId ?? 'part_${dsfDoc.itemName.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')}_${DateTime.now().millisecondsSinceEpoch}';

      final customPolys = List<CadFoldedPolygon3D>.from(foldResult.allPolygons);
      if (customPolys.isEmpty && dsfDoc.outerContour.length >= 3) {
        customPolys.add(
          CadFoldedPolygon3D(
            faceId: 'flat_blank',
            vertices: dsfDoc.outerContour.map((p) => CadPoint3D(p.x, p.y, 0.0)).toList(),
            normal: const CadPoint3D(0.0, 0.0, 1.0),
            color: const Color(0xFF6C9DC6),
          ),
        );
      }

      final part = AssemblyPart(
        id: id,
        name: dsfDoc.itemName.replaceAll('.dsf', '').replaceAll('_', ' '),
        type: partType,
        position: position,
        length: foldResult.boundLength > 0 ? foldResult.boundLength : 300.0,
        height: foldResult.boundHeight > 0 ? foldResult.boundHeight : 50.0,
        thickness: dsfDoc.material.thicknessMm > 0 ? dsfDoc.material.thicknessMm : 1.5,
        color: const Color(0xFF6C9DC6), // Sleek Onshape Cerulean Blue
        customPolygons: customPolys,
        sourceDsfJson: rawJsonStr,
        sourceDsfDocument: dsfDoc,
      );

    return part;
  }

  /// Breaks a procedural [DsfLadderAssembly] into discrete, individually editable [AssemblyPart]s.
  static List<AssemblyPart> decomposeLadderAssembly({
    required DsfLadderAssembly ladderAssembly,
    CadPoint3D basePosition = const CadPoint3D(0.0, 0.0, 0.0),
  }) {
    final parts = <AssemblyPart>[];
    final timeStamp = DateTime.now().millisecondsSinceEpoch;

    final params = ladderAssembly.parameters;
    const double flangeW = 20.0;

    // 1. Left Side Rail
    final leftRail = AssemblyPart(
      id: 'rail_left_$timeStamp',
      name: 'Left Cable Ladder Rail',
      type: AssemblyPartType.straightRail,
      length: params.length,
      height: params.height,
      flangeWidth: flangeW,
      thickness: params.thickness,
      isFlangeOutward: false,
      position: basePosition,
      color: const Color(0xFF6C9DC6),
    );
    parts.add(leftRail);

    // 2. Right Side Rail
    final rightRail = AssemblyPart(
      id: 'rail_right_$timeStamp',
      name: 'Right Cable Ladder Rail',
      type: AssemblyPartType.straightRail,
      length: params.length,
      height: params.height,
      flangeWidth: flangeW,
      thickness: params.thickness,
      isFlangeOutward: true,
      position: CadPoint3D(basePosition.x, basePosition.y + params.width, basePosition.z),
      color: const Color(0xFF6C9DC6),
    );
    parts.add(rightRail);

    // 3. Discrete Rungs
    for (int i = 0; i < ladderAssembly.rungs.length; i++) {
      final rungInst = ladderAssembly.rungs[i];
      final rungId = 'rung_${i + 1}_$timeStamp';

      final rung = AssemblyPart(
        id: rungId,
        name: 'Slotted Rung #${i + 1}',
        type: AssemblyPartType.rung,
        length: params.width + 20.0,
        height: 20.0,
        flangeWidth: 20.0,
        thickness: params.thickness,
        parentPartId: leftRail.id,
        mateStyle: 'passThrough',
        position: CadPoint3D(basePosition.x + rungInst.stationX, basePosition.y - 10.0, basePosition.z + (params.height / 2.0) - 10.0),
        rotationDeg: const CadPoint3D(0.0, 0.0, 90.0),
        color: const Color(0xFF5B8DB8),
        jointType: AssemblyJointType.slotMate,
      );

      parts.add(rung);
    }

    return parts;
  }

  /// Prompts user to pick one or more .dsf files and adds them to the active assembly.
  static Future<int> pickAndImportDsfFiles({
    required BuildContext context,
    required AssemblyStudioViewModel vm,
  }) async {
    try {
      final rawFiles = await StudioFileService.pickRawFiles(allowedExtensions: ['dsf']);
      if (rawFiles.isEmpty) return 0;

      vm.recordUndoCheckpoint();

      int count = 0;
      double offsetX = 0.0;
      double offsetY = 0.0;

      for (final f in rawFiles) {
        if (f.content.trim().isEmpty) continue;
        try {
          final jsonMap = jsonDecode(f.content) as Map<String, dynamic>;
          final dsfDoc = DsfDocument.fromJson(jsonMap);

          final part = convertDsfToAssemblyPart(
            dsfDoc: dsfDoc,
            rawJsonStr: f.content,
            position: CadPoint3D(offsetX, offsetY, 0.0),
          );

          vm.doc.parts.add(part);
          count++;

          // Stagger subsequent imported parts along Y axis
          offsetY += (part.length > 0 ? part.length : 300.0) + 60.0;
        } catch (e) {
          debugPrint('Error parsing picked DSF file ${f.fileName}: $e');
        }
      }

      if (count > 0) {
        vm.invalidateMeshCache();
        vm.notifyDocChanged();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Successfully imported $count DSF part(s) into Assembly Studio.'),
              backgroundColor: const Color(0xFF0284C7),
            ),
          );
        }
      }

      return count;
    } catch (e) {
      debugPrint('Error in pickAndImportDsfFiles: $e');
      return 0;
    }
  }

  /// Prompts user to pick and open a .dam assembly file.
  static Future<bool> pickAndOpenDamFile({
    required BuildContext context,
    required AssemblyStudioViewModel vm,
  }) async {
    try {
      final rawFiles = await StudioFileService.pickRawFiles(allowedExtensions: ['dam', 'json']);
      if (rawFiles.isEmpty) return false;

      final file = rawFiles.first;
      if (file.content.trim().isEmpty) return false;

      final success = importFromDamJson(file.content, vm);
      if (success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Assembly "${vm.doc.title}" loaded successfully (.dam).'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
      return success;
    } catch (e) {
      debugPrint('Error in pickAndOpenDamFile: $e');
      return false;
    }
  }

  /// Saves the active assembly session to a .dam file on disk.
  static Future<String?> saveDamFile({
    required BuildContext context,
    required AssemblyStudioViewModel vm,
    String? customFileName,
  }) async {
    try {
      final content = exportToDamJson(vm);
      final defaultName = customFileName ?? '${vm.doc.title.replaceAll(' ', '_')}.dam';

      final savedPath = await StudioFileService.saveFileAs(
        fileName: defaultName,
        content: content,
        dialogTitle: 'Save Digital Assembly Model (.dam)',
      );

      if (savedPath != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Assembly saved successfully to $defaultName'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
      return savedPath;
    } catch (e) {
      debugPrint('Error saving DAM file: $e');
      return null;
    }
  }

  static Map<String, dynamic> _primitiveToJson(CADPrimitiveEntity p) {
    if (p is CADRectangleEntity) {
      return {
        'type': 'rectangle',
        'id': p.id,
        'sx': p.startPoint.dx,
        'sy': p.startPoint.dy,
        'width': p.width,
        'height': p.height,
        'isConstruction': p.isConstruction,
      };
    } else if (p is CADCenterRectangleEntity) {
      return {
        'type': 'center_rectangle',
        'id': p.id,
        'cx': p.center.dx,
        'cy': p.center.dy,
        'width': p.width,
        'height': p.height,
        'isConstruction': p.isConstruction,
      };
    } else if (p is CADCircleEntity) {
      return {
        'type': 'circle',
        'id': p.id,
        'cx': p.center.dx,
        'cy': p.center.dy,
        'radius': p.radius,
        'isConstruction': p.isConstruction,
      };
    } else if (p is CADLineEntity) {
      return {
        'type': 'line',
        'id': p.id,
        'x1': p.start.dx,
        'y1': p.start.dy,
        'x2': p.end.dx,
        'y2': p.end.dy,
        'isConstruction': p.isConstruction,
      };
    } else if (p is CADPolylineEntity) {
      return {
        'type': 'polyline',
        'id': p.id,
        'points': p.points.map((pt) => [pt.dx, pt.dy]).toList(),
        'isClosed': p.isClosed,
        'isConstruction': p.isConstruction,
      };
    }
    return {'type': 'unknown', 'id': p.id};
  }

  static CADPrimitiveEntity? _primitiveFromJson(Map<String, dynamic> j) {
    final type = j['type'] as String? ?? '';
    final id = j['id'] as String? ?? 'prim_${DateTime.now().microsecondsSinceEpoch}';
    final isConstruction = j['isConstruction'] as bool? ?? false;

    switch (type) {
      case 'rectangle':
        return CADRectangleEntity(
          id: id,
          startPoint: Offset((j['sx'] as num?)?.toDouble() ?? 0.0, (j['sy'] as num?)?.toDouble() ?? 0.0),
          width: (j['width'] as num?)?.toDouble() ?? 100.0,
          height: (j['height'] as num?)?.toDouble() ?? 100.0,
          isConstruction: isConstruction,
        );
      case 'center_rectangle':
        return CADCenterRectangleEntity(
          id: id,
          center: Offset((j['cx'] as num?)?.toDouble() ?? 0.0, (j['cy'] as num?)?.toDouble() ?? 0.0),
          width: (j['width'] as num?)?.toDouble() ?? 100.0,
          height: (j['height'] as num?)?.toDouble() ?? 100.0,
          isConstruction: isConstruction,
        );
      case 'circle':
        return CADCircleEntity(
          id: id,
          center: Offset((j['cx'] as num?)?.toDouble() ?? 0.0, (j['cy'] as num?)?.toDouble() ?? 0.0),
          radius: (j['radius'] as num?)?.toDouble() ?? 25.0,
          isConstruction: isConstruction,
        );
      case 'line':
        return CADLineEntity(
          id: id,
          start: Offset((j['x1'] as num?)?.toDouble() ?? 0.0, (j['y1'] as num?)?.toDouble() ?? 0.0),
          end: Offset((j['x2'] as num?)?.toDouble() ?? 100.0, (j['y2'] as num?)?.toDouble() ?? 100.0),
          isConstruction: isConstruction,
        );
      case 'polyline':
        final rawPts = j['points'] as List? ?? [];
        final points = rawPts.map((p) {
          final pair = p as List;
          return Offset((pair[0] as num).toDouble(), (pair[1] as num).toDouble());
        }).toList();
        return CADPolylineEntity(
          id: id,
          points: points,
          isClosed: j['isClosed'] as bool? ?? true,
          isConstruction: isConstruction,
        );
      default:
        return null;
    }
  }
}
