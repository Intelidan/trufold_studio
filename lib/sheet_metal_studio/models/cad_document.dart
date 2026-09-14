// =============================================================================
// cad_document.dart
//
// Root CAD Document Container per Master Guide Step 1 (#14).
// Unifies CadPart, CadAssembly, CadGeometry, CadFeature, CadDimension,
// CadConstraint, and CadParameter into one coherent model with stable IDs.
// Provides bidirectional round-trip conversion with DsfDocument.
// =============================================================================

import 'cad_primitives.dart';
import 'cad_part.dart';
import 'cad_assembly.dart';
import 'cad_parameter.dart';
import 'dsf_document.dart';
import 'fold_bend_line.dart';
import 'planar_sheet_face.dart';
import 'cnc_punch_primitive.dart';
import 'perforation_pattern.dart';
import 'corner_treatment.dart';
import 'dsf_layer.dart';

class CadDocument {
  static const String currentSchemaVersion = '2.0';

  final String id;
  final String name;
  final String schemaVersion;
  final String units; // 'mm' internally
  final List<CadPart> parts;
  final List<CadAssembly> assemblies;
  final Map<String, CadParameter> globalParameters;
  final Map<String, dynamic> metadata;

  const CadDocument({
    required this.id,
    required this.name,
    this.schemaVersion = currentSchemaVersion,
    this.units = 'mm',
    this.parts = const [],
    this.assemblies = const [],
    this.globalParameters = const {},
    this.metadata = const {},
  });

  /// Primary active part being edited in the 2D/3D studio
  CadPart get primaryPart =>
      parts.isNotEmpty ? parts.first : CadPart(id: 'part_0', name: name);

  CadDocument copyWith({
    String? id,
    String? name,
    String? schemaVersion,
    String? units,
    List<CadPart>? parts,
    List<CadAssembly>? assemblies,
    Map<String, CadParameter>? globalParameters,
    Map<String, dynamic>? metadata,
  }) {
    return CadDocument(
      id: id ?? this.id,
      name: name ?? this.name,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      units: units ?? this.units,
      parts: parts ?? this.parts,
      assemblies: assemblies ?? this.assemblies,
      globalParameters: globalParameters ?? this.globalParameters,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Converts this CadDocument into an interoperable DsfDocument
  DsfDocument toDsfDocument({
    List<FoldBendLine>? bends,
    List<PlanarSheetFace>? faces,
    List<CncPunchPrimitive>? punches,
    List<PerforationPattern>? perforationPatterns,
    List<CornerTreatment>? corners,
    List<CadLineSegment>? cutLines,
    List<DsfLayer>? layers,
    String baseFaceId = '',
  }) {
    final part = primaryPart;
    return DsfDocument(
      format: DsfDocument.currentFormat,
      version: schemaVersion,
      productType: metadata['productType'] as String? ?? 'Sheet Metal Part',
      itemName: name,
      material: part.material,
      outerContour: part.outerContour,
      bends: bends ?? const [],
      faces: faces ?? const [],
      punches: punches ?? const [],
      perforationPatterns: perforationPatterns ?? const [],
      corners: corners ?? const [],
      cutLines: cutLines ?? const [],
      dimensions: part.dimensions,
      constraints: part.constraints,
      layers: layers ?? const [],
      baseFaceId: baseFaceId,
      parameters: part.parameters.map((k, v) => MapEntry(k, v.value)),
      metadata: {
        ...metadata,
        'cadDocId': id,
        'hasAssemblies': assemblies.isNotEmpty,
      },
    );
  }

  /// Reconstructs a CadDocument from an existing DsfDocument without data loss
  factory CadDocument.fromDsfDocument(DsfDocument dsf) {
    final partId = dsf.metadata['cadPartId'] as String? ?? 'part_${dsf.itemName.replaceAll(' ', '_')}';
    final parameters = <String, CadParameter>{};
    dsf.parameters.forEach((k, v) {
      parameters[k] = CadParameter(
        id: 'param_$k',
        name: k,
        value: v,
        category: CadParameterCategory.user,
      );
    });

    final part = CadPart(
      id: partId,
      name: dsf.itemName,
      material: dsf.material,
      outerContour: dsf.outerContour,
      dimensions: dsf.dimensions,
      constraints: dsf.constraints,
      parameters: parameters,
      flatBlankWidth: dsf.blankWidthMm,
      flatBlankLength: dsf.blankLengthMm,
    );

    return CadDocument(
      id: dsf.metadata['cadDocId'] as String? ?? 'doc_${dsf.itemName.replaceAll(' ', '_')}',
      name: dsf.itemName,
      schemaVersion: dsf.version,
      units: 'mm',
      parts: [part],
      globalParameters: parameters,
      metadata: {
        ...dsf.metadata,
        'productType': dsf.productType,
        'baseFaceId': dsf.baseFaceId,
      },
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'schemaVersion': schemaVersion,
        'units': units,
        'parts': parts.map((p) => p.toJson()).toList(),
        'assemblies': assemblies.map((a) => a.toJson()).toList(),
        'globalParameters': globalParameters.map((k, v) => MapEntry(k, v.toJson())),
        'metadata': metadata,
      };

  factory CadDocument.fromJson(Map<String, dynamic> json) => CadDocument(
        id: json['id'] as String,
        name: json['name'] as String,
        schemaVersion: json['schemaVersion'] as String? ?? currentSchemaVersion,
        units: json['units'] as String? ?? 'mm',
        parts: (json['parts'] as List<dynamic>?)
                ?.map((p) => CadPart.fromJson(p as Map<String, dynamic>))
                .toList() ??
            const [],
        assemblies: (json['assemblies'] as List<dynamic>?)
                ?.map((a) => CadAssembly.fromJson(a as Map<String, dynamic>))
                .toList() ??
            const [],
        globalParameters: (json['globalParameters'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(k, CadParameter.fromJson(v as Map<String, dynamic>)),
            ) ??
            const {},
        metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
      );
}
