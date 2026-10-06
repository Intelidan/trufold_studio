import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cnc_punch_primitive.dart';
import 'package:trufold_studio/sheet_metal_studio/models/fold_bend_line.dart';
import 'package:trufold_studio/sheet_metal_studio/models/planar_sheet_face.dart';
import 'package:trufold_studio/sheet_metal_studio/models/sheet_metal_material.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/dxf_dsf_importer.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/planar_face_decomposer.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';
import '../models/vector_cad_entity.dart';
import '../engine/cad_snap_engine.dart';

/// Active drafting tool in the 2D CAD canvas.
enum VectorCadTool {
  select,
  line,
  rect,
  circle,
}

/// Controller managing 2D Vector CAD entities, active tool, selection, and DSF document synchronization.
class VectorCadController extends ChangeNotifier {
  final List<VectorCadEntity> _entities = [];
  final List<List<VectorCadEntity>> _undoStack = [];
  final List<List<VectorCadEntity>> _redoStack = [];
  String? _selectedEntityId;
  VectorCadTool _activeTool = VectorCadTool.select;
  final CadSnapEngine _snapEngine = CadSnapEngine();

  Offset _panOffset = const Offset(150.0, 150.0);
  double _scale = 1.0; // 1.0 = 1px per mm (Scale: 1px = 1mm)
  bool _liveSyncTo3d = true;

  VectorCadEntity? _tempEntity;
  CadSnapResult? _lastSnapResult;

  VectorCadController() {
    loadBlueprintPreset('reducer');
  }

  // Getters
  List<VectorCadEntity> get entities => List.unmodifiable(_entities);
  String? get selectedEntityId => _selectedEntityId;
  VectorCadEntity? get selectedEntity =>
      _entities.where((e) => e.id == _selectedEntityId).firstOrNull;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  bool get liveSyncTo3d => _liveSyncTo3d;
  VectorCadTool get activeTool => _activeTool;
  CadSnapEngine get snapEngine => _snapEngine;
  bool get isGridSnapEnabled => _snapEngine.isGridSnapEnabled;
  double get gridSizeMm => _snapEngine.gridSizeMm;
  Offset get panOffset => _panOffset;
  double get scale => _scale;
  VectorCadEntity? get tempEntity => _tempEntity;
  CadSnapResult? get lastSnapResult => _lastSnapResult;

  int get elementsCount => _entities.length;

  double get selectedPerimeter => selectedEntity?.perimeter ?? 0.0;

  String get selectedScopeLabel {
    if (selectedEntity == null) return 'None';
    return selectedEntity!.label;
  }

  // Tool & Snapping Controls
  void setActiveTool(VectorCadTool tool) {
    if (_activeTool == tool) return;
    _activeTool = tool;
    _tempEntity = null;
    notifyListeners();
  }

  void toggleGridSnap() {
    _snapEngine.isGridSnapEnabled = !_snapEngine.isGridSnapEnabled;
    notifyListeners();
  }

  void setGridSize(double mm) {
    _snapEngine.gridSizeMm = mm;
    notifyListeners();
  }

  void setPanAndScale(Offset pan, double s) {
    _panOffset = pan;
    _scale = s.clamp(0.1, 20.0);
    notifyListeners();
  }

  // Selection & CRUD Operations
  void selectEntity(String? id) {
    if (_selectedEntityId == id) return;
    _selectedEntityId = id;
    for (int i = 0; i < _entities.length; i++) {
      final e = _entities[i];
      if (e.isSelected != (e.id == id)) {
        _entities[i] = e.copyWith(isSelected: e.id == id);
      }
    }
    notifyListeners();
  }

  void selectAt(Offset ptMm) {
    for (int i = _entities.length - 1; i >= 0; i--) {
      if (_entities[i].hitTest(ptMm, 6.0 / _scale)) {
        selectEntity(_entities[i].id);
        return;
      }
    }
    selectEntity(null);
  }

  void setLiveSyncTo3d(bool enabled) {
    if (_liveSyncTo3d == enabled) return;
    _liveSyncTo3d = enabled;
    notifyListeners();
  }

  void _recordHistory() {
    _undoStack.add(List.of(_entities));
    if (_undoStack.length > 50) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void undo() {
    if (!canUndo) return;
    _redoStack.add(List.of(_entities));
    final prev = _undoStack.removeLast();
    _entities.clear();
    _entities.addAll(prev);
    if (!_entities.any((e) => e.id == _selectedEntityId)) {
      _selectedEntityId = null;
    }
    notifyListeners();
  }

  void redo() {
    if (!canRedo) return;
    _undoStack.add(List.of(_entities));
    final nxt = _redoStack.removeLast();
    _entities.clear();
    _entities.addAll(nxt);
    if (!_entities.any((e) => e.id == _selectedEntityId)) {
      _selectedEntityId = null;
    }
    notifyListeners();
  }

  void addEntity(VectorCadEntity entity) {
    _recordHistory();
    _entities.add(entity);
    selectEntity(entity.id);
    notifyListeners();
  }

  void moveSelected(Offset deltaMm) {
    if (_selectedEntityId == null) return;
    final idx = _entities.indexWhere((e) => e.id == _selectedEntityId);
    if (idx < 0) return;
    _entities[idx] = _entities[idx].offsetBy(deltaMm);
    notifyListeners();
  }

  void commitMove() {
    _recordHistory();
  }

  void updateSelectedProperties({
    double? width,
    double? height,
    double? radius,
    double? bendAngleDeg,
    String? bendDirection,
    String? label,
  }) {
    if (_selectedEntityId == null) return;
    final idx = _entities.indexWhere((e) => e.id == _selectedEntityId);
    if (idx < 0) return;
    final cur = _entities[idx];
    _recordHistory();

    if (cur is VectorCadRect) {
      final r = cur.rect;
      final newW = width ?? r.width;
      final newH = height ?? r.height;
      _entities[idx] = cur.copyWith(
        p2: Offset(r.left + newW, r.top + newH),
      );
    } else if (cur is VectorCadCircle) {
      final newR = radius ?? cur.radius;
      _entities[idx] = cur.copyWith(
        radius: newR,
      );
    } else if (cur is VectorCadLine) {
      _entities[idx] = cur.copyWith(
        bendAngleDeg: bendAngleDeg,
        bendDirection: bendDirection,
      );
    }
    notifyListeners();
  }

  void toggleSelectedBendLine({double defaultAngleDeg = 90.0, String defaultDirection = 'UP'}) {
    final entity = selectedEntity;
    if (entity is VectorCadLine) {
      _recordHistory();
      final isCurrentlyBend = entity.role == 'bend' || entity.isDashed;
      final updated = entity.copyWith(
        isDashed: !isCurrentlyBend,
        role: !isCurrentlyBend ? 'bend' : 'perimeter',
        bendAngleDeg: !isCurrentlyBend ? (entity.bendAngleDeg != 0 ? entity.bendAngleDeg : defaultAngleDeg) : 0.0,
        bendDirection: !isCurrentlyBend ? (entity.bendDirection.isNotEmpty ? entity.bendDirection : defaultDirection) : 'UP',
        color: !isCurrentlyBend ? const Color(0xFFF59E0B) : const Color(0xFF00FFCC),
      );
      final idx = _entities.indexWhere((e) => e.id == entity.id);
      if (idx >= 0) {
        _entities[idx] = updated;
        notifyListeners();
      }
    }
  }

  void deleteSelected() {
    if (_selectedEntityId == null) return;
    _recordHistory();
    _entities.removeWhere((e) => e.id == _selectedEntityId);
    _selectedEntityId = null;
    notifyListeners();
  }

  void clearWorkspace() {
    _recordHistory();
    _entities.clear();
    _selectedEntityId = null;
    _tempEntity = null;
    notifyListeners();
  }

  // Drafting Interactive Handlers
  void updateTempEntity(VectorCadEntity? entity) {
    _tempEntity = entity;
    notifyListeners();
  }

  CadSnapResult computeSnap(Offset rawPointMm) {
    final result = _snapEngine.snapPoint(
      rawPointMm: rawPointMm,
      entities: _entities,
    );
    _lastSnapResult = result;
    return result;
  }

  // DSF Document Population & Synchronization
  void loadFromDsfDocument(DsfDocument doc) {
    _entities.clear();
    _selectedEntityId = null;

    // 1. Load planar sheet faces as vector rectangles or polygons
    for (int i = 0; i < doc.faces.length; i++) {
      final f = doc.faces[i];
      final pts = f.vertices.map((p) => Offset(p.x, p.y)).toList();
      if (pts.length == 4) {
        // Compute axis-aligned bounds or polygon
        _entities.add(
          VectorCadPolyline(
            id: 'face_${f.id.isEmpty ? i : f.id}',
            label: 'Face ${f.label.isNotEmpty ? f.label : (i + 1)}',
            layer: 'FACES',
            color: const Color(0xFF00FFCC),
            points: pts,
            isClosed: true,
            isFilled: true,
            fillColor: const Color(0x1A00FFCC),
          ),
        );
      } else if (pts.length > 2) {
        _entities.add(
          VectorCadPolyline(
            id: 'face_${f.id.isEmpty ? i : f.id}',
            label: 'Face ${f.label.isNotEmpty ? f.label : (i + 1)}',
            layer: 'FACES',
            color: const Color(0xFF00FFCC),
            points: pts,
            isClosed: true,
            isFilled: true,
          ),
        );
      }
    }

    // 2. Load fold bend lines as dashed amber lines
    for (int i = 0; i < doc.bends.length; i++) {
      final b = doc.bends[i];
      _entities.add(
        VectorCadLine(
          id: 'bend_${b.id.isEmpty ? i : b.id}',
          label: 'Bend ${i + 1} (${b.targetAngleDeg.toStringAsFixed(0)}°)',
          layer: 'BENDS',
          color: const Color(0xFFF59E0B),
          strokeWidth: 1.8,
          p1: Offset(b.p1.x, b.p1.y),
          p2: Offset(b.p2.x, b.p2.y),
          isDashed: true,
          role: 'bend',
          bendAngleDeg: b.targetAngleDeg,
          bendDirection: b.direction == BendDirection.up ? 'UP' : 'DOWN',
        ),
      );
    }

    // 3. Load punch holes as circular cutouts
    for (int i = 0; i < doc.punches.length; i++) {
      final p = doc.punches[i];
      if (p.type == PunchType.roundHole || p.diameterMm > 0) {
        _entities.add(
          VectorCadCircle(
            id: 'punch_${p.id.isEmpty ? i : p.id}',
            label: 'Punch Hole ${i + 1} (Ø${p.diameterMm.toStringAsFixed(0)})',
            layer: 'PUNCHES',
            color: const Color(0xFF00FFCC),
            center: Offset(p.center.x, p.center.y),
            radius: p.diameterMm > 0 ? p.diameterMm / 2.0 : 15.0,
            isPunch: true,
            punchId: p.id,
            punchRole: p.role.name,
          ),
        );
      } else {
        _entities.add(
          VectorCadRect(
            id: 'slot_${p.id.isEmpty ? i : p.id}',
            label: 'Slot ${i + 1} (${p.widthMm.toStringAsFixed(0)}×${p.lengthMm.toStringAsFixed(0)})',
            layer: 'PUNCHES',
            color: const Color(0xFFA855F7),
            p1: Offset(p.center.x - p.widthMm / 2, p.center.y - p.lengthMm / 2),
            p2: Offset(p.center.x + p.widthMm / 2, p.center.y + p.lengthMm / 2),
          ),
        );
      }
    }

    // 4. Load outer contour if faces were empty
    if (_entities.isEmpty && doc.outerContour.length > 2) {
      _entities.add(
        VectorCadPolyline(
          id: 'outer_contour',
          label: 'Blank Outline',
          layer: 'OUTLINE',
          color: const Color(0xFF00FFCC),
          points: doc.outerContour.map((p) => Offset(p.x, p.y)).toList(),
          isClosed: true,
          isFilled: true,
        ),
      );
    }

    notifyListeners();
  }

  // Load Built-in Blueprint Presets
  void loadBlueprintPreset(String presetKey) {
    _entities.clear();
    _selectedEntityId = null;

    if (presetKey == 'reducer') {
      // Straight Reducer 150x100 to 75x50 pattern matching user screenshot:
      // Large circle on left, dual rectangle chassis in center with 4 punch holes, and side return tab
      _entities.add(
        const VectorCadCircle(
          id: 'circle_1',
          label: 'Circular Port Cutout',
          center: Offset(160.0, 160.0),
          radius: 90.0,
          color: Color(0xFF00FFCC),
        ),
      );

      // Top Flange Rectangle
      _entities.add(
        const VectorCadRect(
          id: 'rect_top',
          label: 'Top Flange 1',
          p1: Offset(320.0, 120.0),
          p2: Offset(580.0, 240.0),
          color: Color(0xFF00FFCC),
        ),
      );

      // Bottom Main Base Rectangle
      _entities.add(
        const VectorCadRect(
          id: 'rect_bottom',
          label: 'Base Plate',
          p1: Offset(320.0, 240.0),
          p2: Offset(580.0, 360.0),
          color: Color(0xFF00FFCC),
        ),
      );

      // Fold Center Bend Line
      _entities.add(
        const VectorCadLine(
          id: 'bend_center',
          label: 'Center Bend (90°)',
          p1: Offset(320.0, 240.0),
          p2: Offset(580.0, 240.0),
          color: Color(0xFF00FFCC),
          isDashed: false,
          role: 'bend',
          bendAngleDeg: 90.0,
        ),
      );

      // 4 Punch Bolt Holes in the flanges
      _entities.add(
        const VectorCadCircle(
          id: 'punch_1',
          label: 'Bolt Hole 1',
          center: Offset(380.0, 170.0),
          radius: 20.0,
          color: Color(0xFF00FFCC),
        ),
      );
      _entities.add(
        const VectorCadCircle(
          id: 'punch_2',
          label: 'Bolt Hole 2',
          center: Offset(520.0, 170.0),
          radius: 20.0,
          color: Color(0xFF00FFCC),
        ),
      );
      _entities.add(
        const VectorCadCircle(
          id: 'punch_3',
          label: 'Bolt Hole 3',
          center: Offset(380.0, 300.0),
          radius: 20.0,
          color: Color(0xFF00FFCC),
        ),
      );
      _entities.add(
        const VectorCadCircle(
          id: 'punch_4',
          label: 'Bolt Hole 4',
          center: Offset(520.0, 300.0),
          radius: 20.0,
          color: Color(0xFF00FFCC),
        ),
      );

      // Side Coupler Ear (Selected with red box by default to match screenshot!)
      final selectedRect = const VectorCadRect(
        id: 'rect_2',
        label: 'Rectangle 2',
        p1: Offset(450.0, 270.0),
        p2: Offset(560.0, 350.0),
        color: Color(0xFF00FFCC),
        isSelected: true,
      );
      _entities.add(selectedRect);
      _selectedEntityId = selectedRect.id;

      // Small secondary inspect square on right
      _entities.add(
        const VectorCadRect(
          id: 'rect_right',
          label: 'Coupler Tab',
          p1: Offset(620.0, 230.0),
          p2: Offset(710.0, 320.0),
          color: Color(0xFF00FFCC),
        ),
      );
    } else if (presetKey == 'chassis') {
      // 4-Flange Formed Electronics Chassis
      _entities.add(
        const VectorCadRect(
          id: 'base_chassis',
          label: 'Chassis Floor',
          p1: Offset(200.0, 150.0),
          p2: Offset(500.0, 350.0),
          color: Color(0xFF00FFCC),
        ),
      );
      _entities.add(
        const VectorCadLine(
          id: 'bend_left',
          label: 'Left Flange Bend',
          p1: Offset(200.0, 150.0),
          p2: Offset(200.0, 350.0),
          color: Color(0xFFF59E0B),
          isDashed: true,
          role: 'bend',
          bendAngleDeg: 90.0,
        ),
      );
      _entities.add(
        const VectorCadLine(
          id: 'bend_right',
          label: 'Right Flange Bend',
          p1: Offset(500.0, 150.0),
          p2: Offset(500.0, 350.0),
          color: Color(0xFFF59E0B),
          isDashed: true,
          role: 'bend',
          bendAngleDeg: 90.0,
        ),
      );
      _entities.add(
        const VectorCadCircle(
          id: 'mount_1',
          label: 'Mounting Standoff 1',
          center: Offset(250.0, 200.0),
          radius: 12.0,
        ),
      );
      _entities.add(
        const VectorCadCircle(
          id: 'mount_2',
          label: 'Mounting Standoff 2',
          center: Offset(450.0, 300.0),
          radius: 12.0,
        ),
      );
    }

    notifyListeners();
  }

  // Ingest raw DSF JSON string directly into 2D canvas
  void loadDsfString(String jsonContent) {
    _recordHistory();
    final doc = DxfDsfImporter.importDsf(jsonContent);
    loadFromDsfDocument(doc);
  }

  // Ingest raw DXF ASCII string into 2D canvas
  void loadDxfString(String dxfContent, {String productType = 'Imported DXF'}) {
    _recordHistory();
    final doc = DxfDsfImporter.importDxf(dxfContent, productType: productType);
    loadFromDsfDocument(doc);
  }

  /// Converts current 2D Vector CAD entities into a fully-structured, fold-ready DsfDocument.
  DsfDocument toDsfDocument({SheetMetalMaterial material = const SheetMetalMaterial(thicknessMm: 1.5)}) {
    // 1. Gather all punches
    final punches = <CncPunchPrimitive>[];
    for (final e in _entities) {
      if (e is VectorCadCircle) {
        punches.add(
          CncPunchPrimitive(
            id: e.punchId.isNotEmpty ? e.punchId : e.id,
            type: PunchType.roundHole,
            center: CadPoint2D(e.center.dx, e.center.dy),
            diameterMm: e.diameter,
            role: e.punchRole == 'coupler' ? CncPunchRole.coupler : CncPunchRole.general,
          ),
        );
      }
    }

    // 2. Gather all bend lines
    final bends = <FoldBendLine>[];
    for (final e in _entities) {
      if (e is VectorCadLine && (e.role == 'bend' || e.isDashed)) {
        bends.add(
          FoldBendLine(
            id: e.id,
            p1: CadPoint2D(e.p1.dx, e.p1.dy),
            p2: CadPoint2D(e.p2.dx, e.p2.dy),
            targetAngleDeg: e.bendAngleDeg != 0 ? e.bendAngleDeg : 90.0,
            direction: e.bendDirection == 'DOWN' ? BendDirection.down : BendDirection.up,
            role: BendLineRole.flange,
            parentFaceId: '',
            childFaceId: '',
          ),
        );
      }
    }

    // 3. Gather cut lines
    final cutLines = <CadLineSegment>[];
    for (final e in _entities) {
      if (e is VectorCadLine && e.role == 'cut' && !e.isDashed) {
        cutLines.add(
          CadLineSegment(
            id: e.id,
            p1: CadPoint2D(e.p1.dx, e.p1.dy),
            p2: CadPoint2D(e.p2.dx, e.p2.dy),
          ),
        );
      }
    }

    // 4. Gather faces from VectorCadRect and VectorCadPolyline
    final rawFaces = <PlanarSheetFace>[];
    for (int i = 0; i < _entities.length; i++) {
      final e = _entities[i];
      if (e is VectorCadRect) {
        final r = e.rect;
        final verts = [
          CadPoint2D(r.left, r.top),
          CadPoint2D(r.right, r.top),
          CadPoint2D(r.right, r.bottom),
          CadPoint2D(r.left, r.bottom),
        ];
        rawFaces.add(
          PlanarSheetFace(
            id: e.faceId.isNotEmpty ? e.faceId : e.id,
            label: e.label.isNotEmpty ? e.label : 'Panel ${i + 1}',
            vertices: verts,
            role: FaceRole.custom,
          ),
        );
      } else if (e is VectorCadPolyline && e.points.length >= 3 && e.layer != 'OUTLINE') {
        rawFaces.add(
          PlanarSheetFace(
            id: e.id,
            label: e.label.isNotEmpty ? e.label : 'Panel ${i + 1}',
            vertices: e.points.map((p) => CadPoint2D(p.dx, p.dy)).toList(),
            role: FaceRole.custom,
          ),
        );
      }
    }

    // 5. Gather outer contour if explicitly defined
    final outlinePoly = _entities.whereType<VectorCadPolyline>().where((p) => p.layer == 'OUTLINE').firstOrNull;
    List<CadPoint2D> outerContour = outlinePoly != null
        ? outlinePoly.points.map((p) => CadPoint2D(p.dx, p.dy)).toList()
        : <CadPoint2D>[];

    // If no explicit faces, but outerContour exists, decompose via PlanarFaceDecomposer
    if (rawFaces.isEmpty && outerContour.length >= 3) {
      final decomp = PlanarFaceDecomposer.decompose(
        outerContour: outerContour,
        bends: bends,
        cutLines: cutLines,
      );
      return DsfDocument(
        version: '1.0',
        productType: '2D CAD Formed Part',
        itemName: 'Canvas Draft',
        material: material,
        outerContour: outerContour,
        faces: decomp.faces,
        bends: decomp.connectedBends,
        baseFaceId: decomp.baseFaceId,
        punches: punches,
        cutLines: cutLines,
      );
    }

    // If faces are explicitly given, find adjacency for each bend
    final connectedBends = <FoldBendLine>[];
    for (final bend in bends) {
      final mid = bend.midpoint;
      final u = bend.unitNormal;
      const probeDist = 3.0;
      final probeA = CadPoint2D(mid.x + u.x * probeDist, mid.y + u.y * probeDist);
      final probeB = CadPoint2D(mid.x - u.x * probeDist, mid.y - u.y * probeDist);

      String faceAId = '';
      String faceBId = '';

      for (final face in rawFaces) {
        if (faceAId.isEmpty && _isPointInPoly(probeA, face.vertices)) {
          faceAId = face.id;
        }
        if (faceBId.isEmpty && _isPointInPoly(probeB, face.vertices)) {
          faceBId = face.id;
        }
      }

      // If probe was ambiguous, fallback to closest centroids
      if (faceAId.isEmpty || faceBId.isEmpty || faceAId == faceBId) {
        final sortedByDist = rawFaces.toList()
          ..sort((f1, f2) => f1.centroid.distanceTo(mid).compareTo(f2.centroid.distanceTo(mid)));
        if (sortedByDist.length >= 2) {
          faceAId = sortedByDist[0].id;
          faceBId = sortedByDist[1].id;
        } else if (sortedByDist.length == 1) {
          faceAId = sortedByDist[0].id;
        }
      }

      connectedBends.add(bend.copyWith(parentFaceId: faceAId, childFaceId: faceBId));
    }

    // 6. Identify base face (largest surface area)
    String baseFaceId = rawFaces.isNotEmpty ? rawFaces.first.id : '';
    double maxArea = -1.0;
    for (final f in rawFaces) {
      final area = f.areaMm2.abs();
      if (area > maxArea) {
        maxArea = area;
        baseFaceId = f.id;
      }
    }

    // Reorient bends so parent-child DAG flows outward from base face
    final orientedBends = <FoldBendLine>[];
    for (final b in connectedBends) {
      if (b.childFaceId == baseFaceId) {
        // Swap so base face is the parent
        orientedBends.add(
          b.copyWith(
            parentFaceId: b.childFaceId,
            childFaceId: b.parentFaceId,
            p1: b.p2,
            p2: b.p1,
          ),
        );
      } else {
        orientedBends.add(b);
      }
    }

    // Finalize faces with semantic roles
    final finalizedFaces = rawFaces.map((f) {
      if (f.id == baseFaceId) {
        return f.copyWith(role: FaceRole.baseFloor, isBaseAnchor: true);
      }
      return f.copyWith(role: FaceRole.sideWall);
    }).toList();

    // If outerContour is empty, compute bounding box of all faces
    if (outerContour.isEmpty && finalizedFaces.isNotEmpty) {
      double minX = double.infinity, minY = double.infinity;
      double maxX = -double.infinity, maxY = -double.infinity;
      for (final f in finalizedFaces) {
        for (final v in f.vertices) {
          if (v.x < minX) minX = v.x;
          if (v.y < minY) minY = v.y;
          if (v.x > maxX) maxX = v.x;
          if (v.y > maxY) maxY = v.y;
        }
      }
      if (minX.isFinite && maxX.isFinite) {
        outerContour = [
          CadPoint2D(minX, minY),
          CadPoint2D(maxX, minY),
          CadPoint2D(maxX, maxY),
          CadPoint2D(minX, maxY),
        ];
      }
    }

    return DsfDocument(
      version: '1.0',
      productType: '2D CAD Formed Part',
      itemName: 'Canvas Draft',
      material: material,
      outerContour: outerContour,
      faces: finalizedFaces,
      bends: orientedBends,
      baseFaceId: baseFaceId,
      punches: punches,
      cutLines: cutLines,
    );
  }

  static bool _isPointInPoly(CadPoint2D pt, List<CadPoint2D> poly) {
    if (poly.length < 3) return false;
    bool inside = false;
    for (int i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final xi = poly[i].x, yi = poly[i].y;
      final xj = poly[j].x, yj = poly[j].y;
      final intersect = ((yi > pt.y) != (yj > pt.y)) &&
          (pt.x < (xj - xi) * (pt.y - yi) / (yj - yi) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  // Bridge to 3D Model: Translates 2D Vector CAD sketch to 3D model in ThreeJS
  void syncToViewModel(SheetMetalStudioViewModel vm) {
    try {
      final dsfDoc = toDsfDocument(material: vm.document.material);
      vm.loadDocument(dsfDoc);
    } catch (e) {
      debugPrint('VectorCadController: Error translating 2D sketch to 3D model: $e');
    }
  }

  // Zoom to fit all entities inside viewport bounds
  void zoomToFit(Size viewportSize) {
    if (_entities.isEmpty) return;
    Rect allBounds = _entities.first.bounds;
    for (final e in _entities) {
      allBounds = allBounds.expandToInclude(e.bounds);
    }
    final pad = 60.0;
    final scaleX = (viewportSize.width - pad * 2) / math.max(allBounds.width, 10.0);
    final scaleY = (viewportSize.height - pad * 2) / math.max(allBounds.height, 10.0);
    final newScale = math.min(scaleX, scaleY).clamp(0.2, 5.0);

    final panX = (viewportSize.width - allBounds.width * newScale) / 2.0 - allBounds.left * newScale;
    final panY = (viewportSize.height - allBounds.height * newScale) / 2.0 - allBounds.top * newScale;

    _panOffset = Offset(panX, panY);
    _scale = newScale;
    notifyListeners();
  }
}
