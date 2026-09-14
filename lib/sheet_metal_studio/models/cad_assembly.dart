// =============================================================================
// cad_assembly.dart
//
// Multi-part assembly and fabrication model per Master Guide #50-#52.
// Represents Cable Ladders (Side rails + Rungs) and multi-part welded fittings.
// =============================================================================

import 'cad_primitives.dart';
import 'cad_parameter.dart';

enum CadWeldType {
  fillet,
  seam,
  tack,
  plug,
  butt,
}

/// Represents a physical weld joining two sheet metal components
class CadWeldLine {
  final String id;
  final CadPoint3D p1;
  final CadPoint3D p2;
  final CadWeldType type;
  final double sizeMm;
  final String? componentAId;
  final String? componentBId;

  const CadWeldLine({
    required this.id,
    required this.p1,
    required this.p2,
    this.type = CadWeldType.fillet,
    this.sizeMm = 3.0,
    this.componentAId,
    this.componentBId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'p1': p1.toJson(),
        'p2': p2.toJson(),
        'type': type.name,
        'sizeMm': sizeMm,
        if (componentAId != null) 'componentAId': componentAId,
        if (componentBId != null) 'componentBId': componentBId,
      };

  factory CadWeldLine.fromJson(Map<String, dynamic> json) => CadWeldLine(
        id: json['id'] as String,
        p1: CadPoint3D.fromJson(json['p1'] as Map<String, dynamic>),
        p2: CadPoint3D.fromJson(json['p2'] as Map<String, dynamic>),
        type: CadWeldType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => CadWeldType.fillet,
        ),
        sizeMm: (json['sizeMm'] as num?)?.toDouble() ?? 3.0,
        componentAId: json['componentAId'] as String?,
        componentBId: json['componentBId'] as String?,
      );
}

/// Instance of a CadPart positioned in 3D assembly space
class CadAssemblyComponentInstance {
  final String instanceId;
  final String partDefinitionId; // Links to CadPart ID or DsfDocument
  final String name;
  final CadPoint3D position;
  final CadPoint3D rotationDeg; // Euler angles in degrees
  final int quantity;
  final bool isPatterned;
  final String? patternParentId;
  final bool isVisible;

  const CadAssemblyComponentInstance({
    required this.instanceId,
    required this.partDefinitionId,
    required this.name,
    this.position = const CadPoint3D(0, 0, 0),
    this.rotationDeg = const CadPoint3D(0, 0, 0),
    this.quantity = 1,
    this.isPatterned = false,
    this.patternParentId,
    this.isVisible = true,
  });

  CadAssemblyComponentInstance copyWith({
    String? instanceId,
    String? partDefinitionId,
    String? name,
    CadPoint3D? position,
    CadPoint3D? rotationDeg,
    int? quantity,
    bool? isPatterned,
    String? patternParentId,
    bool? isVisible,
  }) {
    return CadAssemblyComponentInstance(
      instanceId: instanceId ?? this.instanceId,
      partDefinitionId: partDefinitionId ?? this.partDefinitionId,
      name: name ?? this.name,
      position: position ?? this.position,
      rotationDeg: rotationDeg ?? this.rotationDeg,
      quantity: quantity ?? this.quantity,
      isPatterned: isPatterned ?? this.isPatterned,
      patternParentId: patternParentId ?? this.patternParentId,
      isVisible: isVisible ?? this.isVisible,
    );
  }

  Map<String, dynamic> toJson() => {
        'instanceId': instanceId,
        'partDefinitionId': partDefinitionId,
        'name': name,
        'position': position.toJson(),
        'rotationDeg': rotationDeg.toJson(),
        'quantity': quantity,
        'isPatterned': isPatterned,
        if (patternParentId != null) 'patternParentId': patternParentId,
        'isVisible': isVisible,
      };

  factory CadAssemblyComponentInstance.fromJson(Map<String, dynamic> json) =>
      CadAssemblyComponentInstance(
        instanceId: json['instanceId'] as String,
        partDefinitionId: json['partDefinitionId'] as String,
        name: json['name'] as String,
        position: json['position'] != null
            ? CadPoint3D.fromJson(json['position'] as Map<String, dynamic>)
            : const CadPoint3D(0, 0, 0),
        rotationDeg: json['rotationDeg'] != null
            ? CadPoint3D.fromJson(json['rotationDeg'] as Map<String, dynamic>)
            : const CadPoint3D(0, 0, 0),
        quantity: json['quantity'] as int? ?? 1,
        isPatterned: json['isPatterned'] as bool? ?? false,
        patternParentId: json['patternParentId'] as String?,
        isVisible: json['isVisible'] as bool? ?? true,
      );
}

/// Root assembly entity containing multiple part instances and welds
class CadAssembly {
  final String id;
  final String name;
  final String productType; // e.g. 'Cable Ladder', 'Fabricated Fitting'
  final List<CadAssemblyComponentInstance> components;
  final List<CadWeldLine> welds;
  final Map<String, CadParameter> parameters;
  final Map<String, dynamic> metadata;

  const CadAssembly({
    required this.id,
    required this.name,
    this.productType = 'Assembly',
    this.components = const [],
    this.welds = const [],
    this.parameters = const {},
    this.metadata = const {},
  });

  /// Total count of all components including pattern quantities
  int get totalComponentCount => components.fold(0, (sum, c) => sum + c.quantity);

  CadAssembly copyWith({
    String? id,
    String? name,
    String? productType,
    List<CadAssemblyComponentInstance>? components,
    List<CadWeldLine>? welds,
    Map<String, CadParameter>? parameters,
    Map<String, dynamic>? metadata,
  }) {
    return CadAssembly(
      id: id ?? this.id,
      name: name ?? this.name,
      productType: productType ?? this.productType,
      components: components ?? this.components,
      welds: welds ?? this.welds,
      parameters: parameters ?? this.parameters,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'productType': productType,
        'components': components.map((c) => c.toJson()).toList(),
        'welds': welds.map((w) => w.toJson()).toList(),
        'parameters': parameters.map((k, v) => MapEntry(k, v.toJson())),
        'metadata': metadata,
      };

  factory CadAssembly.fromJson(Map<String, dynamic> json) => CadAssembly(
        id: json['id'] as String,
        name: json['name'] as String,
        productType: json['productType'] as String? ?? 'Assembly',
        components: (json['components'] as List<dynamic>?)
                ?.map((c) => CadAssemblyComponentInstance.fromJson(c as Map<String, dynamic>))
                .toList() ??
            const [],
        welds: (json['welds'] as List<dynamic>?)
                ?.map((w) => CadWeldLine.fromJson(w as Map<String, dynamic>))
                .toList() ??
            const [],
        parameters: (json['parameters'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(k, CadParameter.fromJson(v as Map<String, dynamic>)),
            ) ??
            const {},
        metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
      );
}
