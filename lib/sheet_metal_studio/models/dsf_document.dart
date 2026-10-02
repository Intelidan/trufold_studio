// =============================================================================
// dsf_document.dart
//
// Danish Sheet Fold (.dsf) File Specification & Data Model.
// A self-contained, portable sheet metal definition format storing 2D cutting
// boundaries, CNC punches, press-brake bend kinematics, and product parameters.
// =============================================================================

import 'dart:convert';
import 'cad_primitives.dart';
import 'sheet_metal_material.dart';
import 'fold_bend_line.dart';
import 'planar_sheet_face.dart';
import 'cnc_punch_primitive.dart';
import 'corner_treatment.dart';
import 'dsf_layer.dart';
import 'perforation_pattern.dart';
import 'cad_document.dart';
import 'cad_dimension.dart';
import 'cad_constraint.dart';
import 'constraints/constraint_definition.dart';
import 'constraints/reference_geometry.dart';
import 'template_parameter_definition.dart';
import 'cms/cms_product_contract.dart';
import 'trunking_cover_data.dart';
import '../engine/planar_face_decomposer.dart';

class DsfDocument {
  static const String currentFormat = 'DANISH_SHEET_FOLD';
  static const String currentVersion = '2.0';

  final String format;
  final String version;
  final String productType;
  final String itemName;
  final SheetMetalMaterial material;
  final List<CadPoint2D> outerContour;
  final String outerContourLayer;
  final List<FoldBendLine> bends;
  final List<PlanarSheetFace> faces;
  final List<CncPunchPrimitive> punches;
  final List<PerforationPattern> perforationPatterns;
  final List<CornerTreatment> corners;
  final List<CadLineSegment> cutLines;
  final List<CadArc2D> arcs;
  final List<CadDimension> dimensions;
  final List<CadConstraint> constraints;
  final List<ConstraintDefinition> constraintDefinitions;
  final List<ReferenceGeometry> referenceGeometries;
  final List<TemplateParameterDefinition> templateParameters;
  final List<DsfLayer> layers;
  final String baseFaceId;
  final Map<String, double> edgeChamfers;
  final Map<String, double> parameters;
  final Map<String, dynamic> metadata;
  final TrunkingCoverData? cover;

  const DsfDocument({
    this.format = currentFormat,
    this.version = currentVersion,
    required this.productType,
    required this.itemName,
    this.material = const SheetMetalMaterial(),
    required this.outerContour,
    this.outerContourLayer = 'OUTLINE',
    required this.bends,
    this.faces = const [],
    this.punches = const [],
    this.perforationPatterns = const [],
    this.corners = const [],
    this.cutLines = const [],
    this.arcs = const [],
    this.dimensions = const [],
    this.constraints = const [],
    this.constraintDefinitions = const [],
    this.referenceGeometries = const [],
    this.templateParameters = const [],
    this.layers = const [],
    this.baseFaceId = '',
    this.edgeChamfers = const {},
    this.parameters = const {},
    this.metadata = const {},
    this.cover,
  });

  /// Returns all active visible punches, combining standalone punches and expanded perforation pattern holes
  List<CncPunchPrimitive> get allPunches => [
        ...punches.where((p) => p.isVisible),
        ...perforationPatterns
            .where((p) {
              if (!p.isVisible) return false;
              if (p.targetFaceId != null) {
                final f = faces.cast<PlanarSheetFace?>().firstWhere(
                      (face) => face?.id == p.targetFaceId,
                      orElse: () => null,
                    );
                if (f != null && !f.isVisible) return false;
              }
              return true;
            })
            .expand((p) => p.expandToPunches().where((hp) => hp.isVisible)),
      ];

  /// Raw unfiltered punches including suppressed entities
  List<CncPunchPrimitive> get allPunchesRaw => [
        ...punches,
        ...perforationPatterns.expand((p) => p.expandToPunches()),
      ];

  /// Returns active layer list or default sheet metal CAD layers
  List<DsfLayer> get effectiveLayers =>
      layers.isNotEmpty ? layers : DsfLayer.defaultLayers();

  String get productTypeName => productType;
  String get partNumber => itemName;

  /// Blank bounding dimensions (for rectangular laser nesting stock)
  double get blankWidthMm {
    if (outerContour.isEmpty) return 0.0;
    double minX = outerContour.first.x, maxX = outerContour.first.x;
    for (final pt in outerContour) {
      if (pt.x < minX) minX = pt.x;
      if (pt.x > maxX) maxX = pt.x;
    }
    return maxX - minX;
  }

  double get blankLengthMm {
    if (outerContour.isEmpty) return 0.0;
    double minY = outerContour.first.y, maxY = outerContour.first.y;
    for (final pt in outerContour) {
      if (pt.y < minY) minY = pt.y;
      if (pt.y > maxY) maxY = pt.y;
    }
    return maxY - minY;
  }

  /// Blank area in m²
  double get blankAreaM2 => (blankWidthMm * blankLengthMm) / 1e6;

  /// Total surface area of all holes (punches + perforation patterns) in mm²
  double get totalHolesAreaMm2 {
    double total = 0.0;
    for (final p in punches) {
      total += p.areaMm2;
    }
    for (final pat in perforationPatterns) {
      total += pat.totalHolesAreaMm2;
    }
    return total;
  }

  /// Blank sheet gross area in mm²
  double get blankAreaMm2 => blankWidthMm * blankLengthMm;

  /// Approximate gross blank weight in kg (without hole volume deduction)
  double get grossWeightKg {
    return (blankAreaMm2 / 1e6) * (material.thicknessMm / 1000.0) * material.densityKgM3;
  }

  /// Exact part weight in kg taking into account material density and hole volume deductions
  double get netWeightKg {
    double surfaceAreaMm2 = 0.0;
    if (faces.isNotEmpty) {
      for (final f in faces) {
        surfaceAreaMm2 += f.areaMm2;
      }
    } else if (outerContour.length >= 3) {
      for (int i = 0; i < outerContour.length; i++) {
        final j = (i + 1) % outerContour.length;
        surfaceAreaMm2 += outerContour[i].x * outerContour[j].y - outerContour[j].x * outerContour[i].y;
      }
      surfaceAreaMm2 = (surfaceAreaMm2 / 2.0).abs();
    } else {
      surfaceAreaMm2 = blankAreaMm2;
    }

    return material.calculateWeightKg(
      areaMm2: surfaceAreaMm2,
      holesAreaMm2: totalHolesAreaMm2,
    );
  }

  /// Part weight in kg (defaulting to net weight sans holes)
  double get weightKg => netWeightKg;

  /// Creates a ready-to-test sample: Cable Tray 100x50x3000mm with 15mm 45° return flanges.
  factory DsfDocument.sampleCableTray({double width = 100.0, double height = 50.0, double length = 3000.0, double flange = 15.0, double thickness = 1.5}) {
    // Cross-section development along X axis:
    // Left Flange (15) | Left Wall (50) | Bed Floor (100) | Right Wall (50) | Right Flange (15)
    final totalW = (flange * 2) + (height * 2) + width; // 15 + 50 + 100 + 50 + 15 = 230mm

    final x0 = 0.0;
    final xB1 = flange; // 15
    final xB2 = flange + height; // 65
    final xB3 = flange + height + width; // 165
    final xB4 = flange + height * 2 + width; // 215
    final x5 = totalW; // 230

    final outerContour = [CadPoint2D(x0, 0.0), CadPoint2D(x5, 0.0), CadPoint2D(x5, length), CadPoint2D(x0, length)];

    final bends = [
      FoldBendLine(
        id: 'B1',
        p1: CadPoint2D(xB1, 0.0),
        p2: CadPoint2D(xB1, length),
        direction: BendDirection.up,
        targetAngleDeg: 45.0,
        radiusMm: 1.5,
        layer: 'BEND_UP',
        parentFaceId: 'F_LEFT_WALL',
        childFaceId: 'F_LEFT_FLANGE',
      ),
      FoldBendLine(
        id: 'B2',
        p1: CadPoint2D(xB2, 0.0),
        p2: CadPoint2D(xB2, length),
        direction: BendDirection.up,
        targetAngleDeg: 90.0,
        radiusMm: 1.5,
        layer: 'BEND_UP',
        parentFaceId: 'F_FLOOR',
        childFaceId: 'F_LEFT_WALL',
      ),
      FoldBendLine(
        id: 'B3',
        p1: CadPoint2D(xB3, 0.0),
        p2: CadPoint2D(xB3, length),
        direction: BendDirection.up,
        targetAngleDeg: 90.0,
        radiusMm: 1.5,
        layer: 'BEND_UP',
        parentFaceId: 'F_FLOOR',
        childFaceId: 'F_RIGHT_WALL',
      ),
      FoldBendLine(
        id: 'B4',
        p1: CadPoint2D(xB4, 0.0),
        p2: CadPoint2D(xB4, length),
        direction: BendDirection.up,
        targetAngleDeg: 45.0,
        radiusMm: 1.5,
        layer: 'BEND_UP',
        parentFaceId: 'F_RIGHT_WALL',
        childFaceId: 'F_RIGHT_FLANGE',
      ),
    ];

    final faces = [
      PlanarSheetFace(
        id: 'F_LEFT_FLANGE',
        label: 'Left Return Flange',
        role: FaceRole.returnFlange,
        vertices: [CadPoint2D(x0, 0.0), CadPoint2D(xB1, 0.0), CadPoint2D(xB1, length), CadPoint2D(x0, length)],
      ),
      PlanarSheetFace(
        id: 'F_LEFT_WALL',
        label: 'Left Side Wall',
        role: FaceRole.sideWall,
        vertices: [CadPoint2D(xB1, 0.0), CadPoint2D(xB2, 0.0), CadPoint2D(xB2, length), CadPoint2D(xB1, length)],
      ),
      PlanarSheetFace(
        id: 'F_FLOOR',
        label: 'Bottom Bed Floor',
        role: FaceRole.baseFloor,
        isBaseAnchor: true,
        vertices: [CadPoint2D(xB2, 0.0), CadPoint2D(xB3, 0.0), CadPoint2D(xB3, length), CadPoint2D(xB2, length)],
      ),
      PlanarSheetFace(
        id: 'F_RIGHT_WALL',
        label: 'Right Side Wall',
        role: FaceRole.sideWall,
        vertices: [CadPoint2D(xB3, 0.0), CadPoint2D(xB4, 0.0), CadPoint2D(xB4, length), CadPoint2D(xB3, length)],
      ),
      PlanarSheetFace(
        id: 'F_RIGHT_FLANGE',
        label: 'Right Return Flange',
        role: FaceRole.returnFlange,
        vertices: [CadPoint2D(xB4, 0.0), CadPoint2D(x5, 0.0), CadPoint2D(x5, length), CadPoint2D(xB4, length)],
      ),
    ];

    return DsfDocument(
      productType: 'Perforated Cable Tray',
      itemName: 'CT-${width.round()}x${height.round()}x${length.round()}',
      material: SheetMetalMaterial(thicknessMm: thickness),
      outerContour: outerContour,
      bends: bends,
      faces: faces,
      baseFaceId: 'F_FLOOR',
      parameters: {'W': width, 'H': height, 'L': length, 'F': flange},
      metadata: {'generator': 'Bonn Sheet Metal Studio', 'standard': 'BS EN 61537'},
    );
  }

  DsfDocument copyWith({
    String? productType,
    String? productTypeName,
    String? itemName,
    String? partNumber,
    SheetMetalMaterial? material,
    List<CadPoint2D>? outerContour,
    String? outerContourLayer,
    List<FoldBendLine>? bends,
    List<PlanarSheetFace>? faces,
    List<CncPunchPrimitive>? punches,
    List<PerforationPattern>? perforationPatterns,
    List<CornerTreatment>? corners,
    List<CadLineSegment>? cutLines,
    List<CadArc2D>? arcs,
    List<CadDimension>? dimensions,
    List<CadConstraint>? constraints,
    List<ConstraintDefinition>? constraintDefinitions,
    List<ReferenceGeometry>? referenceGeometries,
    List<TemplateParameterDefinition>? templateParameters,
    List<DsfLayer>? layers,
    String? baseFaceId,
    Map<String, double>? edgeChamfers,
    Map<String, double>? parameters,
    Map<String, dynamic>? metadata,
    TrunkingCoverData? cover,
    bool clearCover = false,
  }) {
    return DsfDocument(
      format: format,
      version: version,
      productType: productType ?? productTypeName ?? this.productType,
      itemName: itemName ?? partNumber ?? this.itemName,
      material: material ?? this.material,
      outerContour: outerContour ?? this.outerContour,
      outerContourLayer: outerContourLayer ?? this.outerContourLayer,
      bends: bends ?? this.bends,
      faces: faces ?? this.faces,
      punches: punches ?? this.punches,
      perforationPatterns: perforationPatterns ?? this.perforationPatterns,
      corners: corners ?? this.corners,
      cutLines: cutLines ?? this.cutLines,
      arcs: arcs ?? this.arcs,
      dimensions: dimensions ?? this.dimensions,
      constraints: constraints ?? this.constraints,
      constraintDefinitions: constraintDefinitions ?? this.constraintDefinitions,
      referenceGeometries: referenceGeometries ?? this.referenceGeometries,
      templateParameters: templateParameters ?? this.templateParameters,
      layers: layers ?? this.layers,
      baseFaceId: baseFaceId ?? this.baseFaceId,
      edgeChamfers: edgeChamfers ?? this.edgeChamfers,
      parameters: parameters ?? this.parameters,
      metadata: metadata ?? this.metadata,
      cover: clearCover ? null : (cover ?? this.cover),
    );
  }

  Map<String, dynamic> toJson() => {
    'format': format,
    'version': version,
    'productType': productType,
    'itemName': itemName,
    'material': material.toJson(),
    'outerContour': outerContour.map((p) => p.toJson()).toList(),
    'outerContourLayer': outerContourLayer,
    'bends': bends.map((b) => b.toJson()).toList(),
    'faces': faces.map((f) => f.toJson()).toList(),
    'punches': punches.map((p) => p.toJson()).toList(),
    'perforationPatterns': perforationPatterns.map((p) => p.toJson()).toList(),
    'corners': corners.map((c) => c.toJson()).toList(),
    'cutLines': cutLines.map((c) => c.toJson()).toList(),
    'arcs': arcs.map((a) => a.toJson()).toList(),
    'dimensions': dimensions.map((d) => d.toJson()).toList(),
    'constraints': constraints.map((c) => c.toJson()).toList(),
    'constraintDefinitions':
        constraintDefinitions.map((c) => c.toJson()).toList(),
    'referenceGeometries':
        referenceGeometries.map((r) => r.toJson()).toList(),
    'templateParameters':
        templateParameters.map((t) => t.toJson()).toList(),
    'layers': effectiveLayers.map((l) => l.toJson()).toList(),
    'baseFaceId': baseFaceId,
    'edgeChamfers': edgeChamfers,
    'parameters': parameters,
    'metadata': metadata,
    if (cover != null) 'cover': cover!.toJson(),
  };

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory DsfDocument.fromJson(Map<String, dynamic> json) => DsfDocument(
    format: json['format'] as String? ?? currentFormat,
    version: json['version'] as String? ?? currentVersion,
    productType: json['productType'] as String? ?? 'Sheet Metal Part',
    itemName: json['itemName'] as String? ?? 'Unnamed',
    material: json['material'] != null ? SheetMetalMaterial.fromJson(json['material'] as Map<String, dynamic>) : const SheetMetalMaterial(),
    outerContour: (json['outerContour'] as List? ?? []).map((e) => CadPoint2D.fromJson(e as Map<String, dynamic>)).toList(),
    outerContourLayer: json['outerContourLayer'] as String? ?? 'OUTLINE',
    bends: (json['bends'] as List? ?? []).map((e) => FoldBendLine.fromJson(e as Map<String, dynamic>)).toList(),
    faces: (json['faces'] as List? ?? []).map((e) => PlanarSheetFace.fromJson(e as Map<String, dynamic>)).toList(),
    punches: () {
      final meta = json['metadata'] as Map<String, dynamic>? ?? {};
      final cmsTemplate = meta['cmsTemplate'] as Map<String, dynamic>?;
      final couplerSlotIds = (cmsTemplate?['couplerSlotPunchIds'] as List?)?.map((e) => e.toString()).toSet() ?? {};
      final raw = (json['punches'] as List? ?? []).map((e) => CncPunchPrimitive.fromJson(e as Map<String, dynamic>)).toList();
      final baseFaceId = json['baseFaceId'] as String? ?? '';
      final facesList = (json['faces'] as List? ?? []).map((e) => PlanarSheetFace.fromJson(e as Map<String, dynamic>)).toList();
      final floorFace = facesList.where((f) =>
          f.id == baseFaceId ||
          f.role == FaceRole.baseFloor ||
          f.id.toUpperCase().contains('FLOOR') ||
          f.id.toUpperCase().contains('BASE')).firstOrNull;

      return raw.map((p) {
        final isOnFloor = floorFace != null && PlanarFaceDecomposer.isPointInsidePolygon(p.center, floorFace.vertices);
        if (isOnFloor && p.layer.toUpperCase() != 'COUPLER') {
          // Punches located on the bottom base floor are perforations / ventilation, never couplers
          if (p.role == CncPunchRole.coupler) {
            return p.copyWith(role: CncPunchRole.perforation);
          }
          return p;
        }
        if (p.role == CncPunchRole.general && couplerSlotIds.contains(p.id)) {
          return p.copyWith(role: CncPunchRole.coupler);
        }
        return p;
      }).toList();
    }(),
    perforationPatterns: (json['perforationPatterns'] as List? ?? []).map((e) => PerforationPattern.fromJson(e as Map<String, dynamic>)).toList(),
    corners: (json['corners'] as List? ?? []).map((e) => CornerTreatment.fromJson(e as Map<String, dynamic>)).toList(),
    cutLines: (json['cutLines'] as List? ?? []).map((e) => CadLineSegment.fromJson(e as Map<String, dynamic>)).toList(),
    arcs: (json['arcs'] as List? ?? []).map((e) => CadArc2D.fromJson(e as Map<String, dynamic>)).toList(),
    dimensions: (json['dimensions'] as List? ?? []).map((e) => CadDimension.fromJson(e as Map<String, dynamic>)).toList(),
    constraints: (json['constraints'] as List? ?? []).map((e) => CadConstraint.fromJson(e as Map<String, dynamic>)).toList(),
    constraintDefinitions: (json['constraintDefinitions'] as List? ?? [])
        .map((e) => ConstraintDefinition.fromJson(e as Map<String, dynamic>))
        .toList(),
    referenceGeometries: (json['referenceGeometries'] as List? ?? [])
        .map((e) => ReferenceGeometry.fromJson(e as Map<String, dynamic>))
        .toList(),
    templateParameters: (json['templateParameters'] as List? ?? [])
        .map((e) => TemplateParameterDefinition.fromJson(e as Map<String, dynamic>))
        .toList(),
    layers: (json['layers'] as List? ?? []).map((e) => DsfLayer.fromJson(e as Map<String, dynamic>)).toList(),
    baseFaceId: json['baseFaceId'] as String? ?? '',
    edgeChamfers: (json['edgeChamfers'] as Map<String, dynamic>? ?? {}).map((k, v) => MapEntry(k, (v as num).toDouble())),
    parameters: (json['parameters'] as Map<String, dynamic>? ?? {}).map((k, v) => MapEntry(k, (v as num).toDouble())),
    metadata: json['metadata'] as Map<String, dynamic>? ?? {},
    cover: json['cover'] != null ? TrunkingCoverData.fromJson(json['cover'] as Map<String, dynamic>) : null,
  );

  factory DsfDocument.parseJsonString(String jsonString) => DsfDocument.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);

  static DsfDocument fromJsonString(String jsonString) => DsfDocument.parseJsonString(jsonString);

  String toJsonString({bool pretty = true}) {
    if (pretty) {
      return const JsonEncoder.withIndent('  ').convert(toJson());
    }
    return jsonEncode(toJson());
  }

  /// Returns the persistent feature changes history from metadata['featureHistory']
  List<Map<String, dynamic>> get featureHistory {
    final list = metadata['featureHistory'];
    if (list is List) {
      return list
          .whereType<Map<dynamic, dynamic>>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }
    return const [];
  }

  /// Appends an action entry to the persistent feature history audit log
  DsfDocument withAppendedFeatureHistory(Map<String, dynamic> entry) {
    final existing = List<Map<String, dynamic>>.from(featureHistory);
    final nextStep = existing.length + 1;
    final updatedEntry = {'step': nextStep, ...entry};
    existing.add(updatedEntry);
    final newMetadata = Map<String, dynamic>.from(metadata);
    newMetadata['featureHistory'] = existing;
    return copyWith(metadata: newMetadata);
  }

  /// Returns a copy of the document with featureHistory cleared
  DsfDocument withClearedFeatureHistory() {
    final newMetadata = Map<String, dynamic>.from(metadata);
    newMetadata.remove('featureHistory');
    newMetadata.remove('undoDeltas');
    return copyWith(metadata: newMetadata);
  }

  /// Returns the serialized undo deltas from metadata['undoDeltas']
  List<Map<String, dynamic>> get undoDeltas {
    final list = metadata['undoDeltas'];
    if (list is List) {
      return list
          .whereType<Map<dynamic, dynamic>>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }
    return const [];
  }

  /// Returns a copy of the document with updated undoDeltas in metadata
  DsfDocument withUndoDeltas(List<Map<String, dynamic>> deltas) {
    final newMetadata = Map<String, dynamic>.from(metadata);
    newMetadata['undoDeltas'] = deltas;
    return copyWith(metadata: newMetadata);
  }

  /// Converts this DsfDocument into a semantic CadDocument model
  CadDocument toCadDocument() => CadDocument.fromDsfDocument(this);

  /// Creates a DsfDocument from a semantic CadDocument model
  factory DsfDocument.fromCadDocument(CadDocument cadDoc) => cadDoc.toDsfDocument();

  /// Whether this document represents a Cable Management System (CMS) fitting/accessory drawing.
  bool get isCmsDrawing {
    // 1. Explicit CMS template / workflow metadata
    if (metadata.containsKey('cmsTemplate') ||
        metadata.containsKey('cms_template') ||
        metadata.containsKey('cmsWorkflow') ||
        metadata.containsKey('cms_workflow') ||
        metadata.containsKey('cms_product_contract') ||
        metadata.containsKey('cmsPorts') ||
        metadata.containsKey('cms_ports')) {
      return true;
    }

    // 2. Explicit fitting metadata indicating an accessory / fitting
    final fittingMeta = metadata['fittingMetadata'];
    if (fittingMeta is Map) {
      final cat = fittingMeta['category']?.toString() ?? '';
      final prod = fittingMeta['product']?.toString() ?? '';
      if (cat.isNotEmpty && cat != 'None' && prod.isNotEmpty && prod != 'None') {
        return true;
      }
    }

    // 3. Document productType / itemName maps to a known CMS Product Contract
    final contract = CmsProductContract.lookup(productType, itemName) ??
        CmsProductContract.lookup(null, itemName) ??
        CmsProductContract.lookup(null, productType);
    if (contract != null) {
      return true;
    }

    return false;
  }

  /// Resolves the product category stored in this document (e.g. 'Trunking Accessories', 'Tray Accessories').
  String get category {
    if (metadata['category'] != null && metadata['category'].toString().isNotEmpty) {
      return metadata['category'].toString();
    }
    if (metadata['fittingCategory'] != null && metadata['fittingCategory'].toString().isNotEmpty) {
      return metadata['fittingCategory'].toString();
    }
    final fittingMeta = metadata['fittingMetadata'];
    if (fittingMeta is Map && fittingMeta['category'] != null && fittingMeta['category'].toString().isNotEmpty && fittingMeta['category'] != 'None') {
      return fittingMeta['category'].toString();
    }
    final cms = metadata['cmsTemplate'];
    if (cms is Map && cms['category'] != null && cms['category'].toString().isNotEmpty) {
      return cms['category'].toString();
    }
    if (templateParameters.isNotEmpty && templateParameters.first.category.isNotEmpty) {
      return templateParameters.first.category;
    }
    return '';
  }
}
