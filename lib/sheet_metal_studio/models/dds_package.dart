// =============================================================================
// dds_package.dart
//
// Danish Datasheet (.dds) Package Specification.
// An all-in-one comprehensive engineering container storing:
// 1. Full 2D & 3D Kinematic Sheet Metal Model (.dsf format embedded)
// 2. Datasheet approval metadata (Customer, Project, Drawing No, Revisions)
// 3. Press brake tooling setup (V-die width, punch radius, bend sequence)
// 4. Studio viewport display states (3D camera orbit, fold progress)
// Designed with ZERO external dependencies for 100% standalone portability.
// =============================================================================

import 'dart:convert';
import 'dsf_document.dart';

class DdsPackage {
  final String version;
  final String format; // 'Danish Datasheet (.dds)'
  final String exportDate;
  final DsfDocument document;
  final Map<String, dynamic> metadata;
  final Map<String, dynamic> viewSettings;
  final List<Map<String, dynamic>> pressBrakeSequence;

  const DdsPackage({
    this.version = '1.0.0',
    this.format = 'Danish Datasheet (.dds)',
    required this.exportDate,
    required this.document,
    this.metadata = const {},
    this.viewSettings = const {},
    this.pressBrakeSequence = const [],
  });

  /// Creates a ready-to-export package from a document and current studio view state
  factory DdsPackage.create({
    required DsfDocument document,
    String projectName = '',
    String customerName = '',
    String drawingNumber = '',
    String drawnBy = 'Engineering Team',
    String checkedBy = 'QA Lead',
    double orbitAngleX = -0.5,
    double orbitAngleY = 0.6,
    double foldProgress = 1.0,
    bool showWireframe = true,
  }) {
    // Generate recommended press-brake sequence
    final seq = <Map<String, dynamic>>[];
    final t = document.material.thicknessMm;
    final recommendedVDie = t <= 2.0 ? t * 6.0 : t * 8.0;

    int stepNum = 1;
    for (final bend in document.bends) {
      seq.add({
        'step': stepNum++,
        'bendId': bend.id,
        'direction': bend.direction.name,
        'targetAngleDeg': bend.targetAngleDeg,
        'bendRadiusMm': bend.radiusMm,
        'recommendedVDieMm': recommendedVDie,
        'lengthMm': (bend.p2 - bend.p1).length,
      });
    }

    return DdsPackage(
      exportDate: DateTime.now().toIso8601String(),
      document: document,
      metadata: {
        'projectName': projectName,
        'customerName': customerName,
        'drawingNumber': drawingNumber.isNotEmpty ? drawingNumber : document.partNumber,
        'drawnBy': drawnBy,
        'checkedBy': checkedBy,
        'productType': document.productTypeName,
      },
      viewSettings: {
        'orbitAngleX': orbitAngleX,
        'orbitAngleY': orbitAngleY,
        'foldProgress': foldProgress,
        'showWireframe': showWireframe,
      },
      pressBrakeSequence: seq,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'format': format,
        'exportDate': exportDate,
        'document': document.toJson(),
        'metadata': metadata,
        'viewSettings': viewSettings,
        'pressBrakeSequence': pressBrakeSequence,
      };

  factory DdsPackage.fromJson(Map<String, dynamic> json) {
    return DdsPackage(
      version: json['version'] as String? ?? '1.0.0',
      format: json['format'] as String? ?? 'Danish Datasheet (.dds)',
      exportDate: json['exportDate'] as String? ?? '',
      document: DsfDocument.fromJson(json['document'] as Map<String, dynamic>),
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
      viewSettings: json['viewSettings'] as Map<String, dynamic>? ?? {},
      pressBrakeSequence: (json['pressBrakeSequence'] as List<dynamic>?)
              ?.map((e) => e as Map<String, dynamic>)
              .toList() ??
          [],
    );
  }

  String toJsonString({bool pretty = true}) {
    if (pretty) {
      return const JsonEncoder.withIndent('  ').convert(toJson());
    }
    return jsonEncode(toJson());
  }
}
