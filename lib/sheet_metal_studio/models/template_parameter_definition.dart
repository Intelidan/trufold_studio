// =============================================================================
// template_parameter_definition.dart
//
// Model for parameter-driven CAD templates and topological zone morphing rules
// per Phase 1 Master Guide (#36-#48, P19-P22).
// Enables single DXF templates to be parametrically morphed without distorting
// corner relief miters, coupler punch clusters, or flange heights.
// =============================================================================

import 'cad_parameter.dart';

enum TopologicalZoneType {
  /// Rigid translation only: e.g. corner relief miters, coupler hole tabs.
  /// Vertices inside retain their exact relative distances without scaling.
  rigidAnchor,

  /// Expands or contracts along the X axis based on width delta.
  stretchX,

  /// Expands or contracts along the Y axis based on length/branch delta.
  stretchY,

  /// Adjusts wall flange height based on height delta.
  stretchFlange,

  /// Bed floor boundary where perforation patterns are parametrically re-nested.
  renestPerforations,
}

/// A spatial or feature-based zone rule dictating how vertices and entities morph.
class TopologicalZoneRule {
  final String id;
  final TopologicalZoneType type;

  /// Normalized bounding box relative to part blank: [minX, maxX, minY, maxY] (0.0 to 1.0)
  /// or null if applied globally / by feature tag.
  final List<double>? normalizedBounds;

  /// Multiplier for X movement (e.g. 0.0 for fixed, 0.5 for centered expansion, 1.0 for end tabs)
  final double dxFactor;

  /// Multiplier for Y movement
  final double dyFactor;

  /// Name of parameter driving this zone
  final String drivingParamKey;

  const TopologicalZoneRule({
    required this.id,
    required this.type,
    this.normalizedBounds,
    this.dxFactor = 1.0,
    this.dyFactor = 1.0,
    this.drivingParamKey = 'width',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    if (normalizedBounds != null) 'normalizedBounds': normalizedBounds,
    'dxFactor': dxFactor,
    'dyFactor': dyFactor,
    'drivingParamKey': drivingParamKey,
  };

  factory TopologicalZoneRule.fromJson(Map<String, dynamic> json) =>
      TopologicalZoneRule(
        id: json['id'] as String,
        type: TopologicalZoneType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => TopologicalZoneType.rigidAnchor,
        ),
        normalizedBounds: (json['normalizedBounds'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList(),
        dxFactor: (json['dxFactor'] as num?)?.toDouble() ?? 1.0,
        dyFactor: (json['dyFactor'] as num?)?.toDouble() ?? 1.0,
        drivingParamKey: json['drivingParamKey'] as String? ?? 'width',
      );
}

/// Represents an entry/exit port on a sheet metal fitting (e.g. cable tray, trunking, duct)
class TemplatePortDefinition {
  final int portIndex; // 1-indexed (e.g. 1, 2, 3, 4)
  final String name; // e.g. "Entry Port 1", "Main Out Port 2", "Branch Port 3"
  final String widthParamKey; // e.g. "port1Width" or "width"
  final String heightParamKey; // e.g. "port1Height" or "height"
  final double defaultWidth;
  final double defaultHeight;
  final String? description;

  const TemplatePortDefinition({
    required this.portIndex,
    required this.name,
    required this.widthParamKey,
    required this.heightParamKey,
    this.defaultWidth = 100.0,
    this.defaultHeight = 50.0,
    this.description,
  });

  Map<String, dynamic> toJson() => {
    'portIndex': portIndex,
    'name': name,
    'widthParamKey': widthParamKey,
    'heightParamKey': heightParamKey,
    'defaultWidth': defaultWidth,
    'defaultHeight': defaultHeight,
    if (description != null) 'description': description,
  };

  factory TemplatePortDefinition.fromJson(Map<String, dynamic> json) =>
      TemplatePortDefinition(
        portIndex: (json['portIndex'] as num?)?.toInt() ?? 1,
        name: json['name'] as String? ?? 'Port 1',
        widthParamKey: json['widthParamKey'] as String? ?? 'width',
        heightParamKey: json['heightParamKey'] as String? ?? 'height',
        defaultWidth: (json['defaultWidth'] as num?)?.toDouble() ?? 100.0,
        defaultHeight: (json['defaultHeight'] as num?)?.toDouble() ?? 50.0,
        description: json['description'] as String?,
      );
}

/// Full specification for a parameter-driven product template.
class TemplateParameterDefinition {
  final String templateId;
  final String name;
  final String category;
  final String productType;
  final String? sourceDxfPath;
  final List<CadParameter> parameters;
  final Map<String, double> baselineParameters;
  final List<TopologicalZoneRule> zoneRules;
  final List<TemplatePortDefinition> ports;

  const TemplateParameterDefinition({
    required this.templateId,
    required this.name,
    required this.category,
    required this.productType,
    this.sourceDxfPath,
    required this.parameters,
    required this.baselineParameters,
    this.zoneRules = const [],
    this.ports = const [],
  });

  CadParameter? getParameter(String key) {
    try {
      return parameters.firstWhere((p) => p.name == key || p.id == key);
    } catch (_) {
      return null;
    }
  }

  Map<String, double> get currentValues {
    final map = <String, double>{};
    for (final p in parameters) {
      map[p.id] = p.value;
    }
    return map;
  }

  Map<String, dynamic> toJson() => {
    'templateId': templateId,
    'name': name,
    'category': category,
    'productType': productType,
    if (sourceDxfPath != null) 'sourceDxfPath': sourceDxfPath,
    'parameters': parameters.map((p) => p.toJson()).toList(),
    'baselineParameters': baselineParameters,
    'zoneRules': zoneRules.map((r) => r.toJson()).toList(),
    if (ports.isNotEmpty) 'ports': ports.map((p) => p.toJson()).toList(),
  };

  factory TemplateParameterDefinition.fromJson(Map<String, dynamic> json) =>
      TemplateParameterDefinition(
        templateId: json['templateId'] as String,
        name: json['name'] as String,
        category: json['category'] as String,
        productType: json['productType'] as String,
        sourceDxfPath: json['sourceDxfPath'] as String?,
        parameters: (json['parameters'] as List? ?? [])
            .map((p) => CadParameter.fromJson(p as Map<String, dynamic>))
            .toList(),
        baselineParameters: (json['baselineParameters'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, (v as num).toDouble())),
        zoneRules: (json['zoneRules'] as List? ?? [])
            .map((r) => TopologicalZoneRule.fromJson(r as Map<String, dynamic>))
            .toList(),
        ports: (json['ports'] as List? ?? [])
            .map((p) => TemplatePortDefinition.fromJson(p as Map<String, dynamic>))
            .toList(),
      );

  // ===========================================================================
  // Standard Factory Presets from product_variations.csv & assets/dxf_templates
  // ===========================================================================

  /// Cable Tray Equal / Unequal Tee Template
  factory TemplateParameterDefinition.cableTrayTee({
    double width = 100.0,
    double branchWidth = 100.0,
    double height = 50.0,
  }) {
    return TemplateParameterDefinition(
      templateId: 'tray_tee',
      name: 'Cable Tray Equal / Unequal Tee',
      category: 'Tray Accessories',
      productType: 'Cable Tray Tee',
      sourceDxfPath: 'assets/dxf_templates/tray_accessories/unequal_tee_100x50x100x50.dxf',
      ports: [
        TemplatePortDefinition(
          portIndex: 1,
          name: 'Main Run In (Port 1)',
          widthParamKey: 'width',
          heightParamKey: 'height',
          defaultWidth: width,
          defaultHeight: height,
        ),
        TemplatePortDefinition(
          portIndex: 2,
          name: 'Main Run Out (Port 2)',
          widthParamKey: 'width',
          heightParamKey: 'height',
          defaultWidth: width,
          defaultHeight: height,
        ),
        TemplatePortDefinition(
          portIndex: 3,
          name: 'Tee Branch (Port 3)',
          widthParamKey: 'branchWidth',
          heightParamKey: 'height',
          defaultWidth: branchWidth,
          defaultHeight: height,
        ),
      ],
      parameters: [
        CadParameter(
          id: 'width',
          name: 'Main Width',
          value: width,
          unit: 'mm',
          minValue: 50.0,
          maxValue: 900.0,
          step: 25.0,
          allowedValues: [50, 75, 100, 150, 200, 300, 450, 600, 750, 900],
          description: 'Width of the through main channel bed',
        ),
        CadParameter(
          id: 'branchWidth',
          name: 'Branch Width',
          value: branchWidth,
          unit: 'mm',
          minValue: 50.0,
          maxValue: 900.0,
          step: 25.0,
          allowedValues: [50, 75, 100, 150, 200, 300, 450, 600, 750, 900],
          description: 'Width of the 90° tee branch bed',
        ),
        CadParameter(
          id: 'height',
          name: 'Side Flange Height',
          value: height,
          unit: 'mm',
          minValue: 25.0,
          maxValue: 150.0,
          step: 25.0,
          allowedValues: [25, 50, 75, 100, 125, 150],
          description: 'Flange wall height for all branches',
        ),
      ],
      baselineParameters: {
        'width': width,
        'branchWidth': branchWidth,
        'height': height,
      },
      zoneRules: const [
        TopologicalZoneRule(
          id: 'right_flange_tab',
          type: TopologicalZoneType.rigidAnchor,
          normalizedBounds: [0.75, 1.0, 0.0, 1.0],
          dxFactor: 1.0,
          dyFactor: 0.0,
          drivingParamKey: 'width',
        ),
        TopologicalZoneRule(
          id: 'branch_top_tab',
          type: TopologicalZoneType.rigidAnchor,
          normalizedBounds: [0.0, 1.0, 0.75, 1.0],
          dxFactor: 0.0,
          dyFactor: 1.0,
          drivingParamKey: 'branchWidth',
        ),
        TopologicalZoneRule(
          id: 'main_floor_span',
          type: TopologicalZoneType.stretchX,
          normalizedBounds: [0.25, 0.75, 0.0, 0.50],
          dxFactor: 1.0,
          dyFactor: 0.0,
          drivingParamKey: 'width',
        ),
        TopologicalZoneRule(
          id: 'branch_floor_span',
          type: TopologicalZoneType.stretchY,
          normalizedBounds: [0.25, 0.75, 0.50, 0.75],
          dxFactor: 0.0,
          dyFactor: 1.0,
          drivingParamKey: 'branchWidth',
        ),
      ],
    );
  }

  /// Cable Tray Unequal Tee with 3 Independent Entry Ports (W1xH1, W2xH2, W3xH3)
  factory TemplateParameterDefinition.cableTrayUnequalTee({
    double port1Width = 200.0,
    double port1Height = 100.0,
    double port2Width = 150.0,
    double port2Height = 100.0,
    double port3Width = 50.0,
    double port3Height = 50.0,
  }) {
    return TemplateParameterDefinition(
      templateId: 'tray_unequal_tee',
      name: 'Cable Tray Unequal Tee (3 Distinct Ports)',
      category: 'Tray Accessories',
      productType: 'Cable Tray Unequal Tee',
      sourceDxfPath: 'assets/dxf_templates/tray_accessories/unequal_tee_100x50x100x50.dxf',
      ports: [
        TemplatePortDefinition(
          portIndex: 1,
          name: 'Entry Part 1 (Main In)',
          widthParamKey: 'port1Width',
          heightParamKey: 'port1Height',
          defaultWidth: port1Width,
          defaultHeight: port1Height,
          description: 'Primary entry feeder channel',
        ),
        TemplatePortDefinition(
          portIndex: 2,
          name: 'Entry Part 2 (Main Out)',
          widthParamKey: 'port2Width',
          heightParamKey: 'port2Height',
          defaultWidth: port2Width,
          defaultHeight: port2Height,
          description: 'Through-run continuation channel',
        ),
        TemplatePortDefinition(
          portIndex: 3,
          name: 'Entry Part 3 (Tee Branch)',
          widthParamKey: 'port3Width',
          heightParamKey: 'port3Height',
          defaultWidth: port3Width,
          defaultHeight: port3Height,
          description: '90° lateral tap branch',
        ),
      ],
      parameters: [
        CadParameter(
          id: 'port1Width',
          name: 'Part 1 Width (W1)',
          value: port1Width,
          unit: 'mm',
          minValue: 50.0,
          maxValue: 900.0,
          step: 25.0,
          allowedValues: [50, 75, 100, 150, 200, 250, 300, 450, 600, 750, 900],
        ),
        CadParameter(
          id: 'port1Height',
          name: 'Part 1 Height (H1)',
          value: port1Height,
          unit: 'mm',
          minValue: 25.0,
          maxValue: 150.0,
          step: 25.0,
          allowedValues: [25, 50, 75, 100, 125, 150],
        ),
        CadParameter(
          id: 'port2Width',
          name: 'Part 2 Width (W2)',
          value: port2Width,
          unit: 'mm',
          minValue: 50.0,
          maxValue: 900.0,
          step: 25.0,
          allowedValues: [50, 75, 100, 150, 200, 250, 300, 450, 600, 750, 900],
        ),
        CadParameter(
          id: 'port2Height',
          name: 'Part 2 Height (H2)',
          value: port2Height,
          unit: 'mm',
          minValue: 25.0,
          maxValue: 150.0,
          step: 25.0,
          allowedValues: [25, 50, 75, 100, 125, 150],
        ),
        CadParameter(
          id: 'port3Width',
          name: 'Part 3 Width (W3)',
          value: port3Width,
          unit: 'mm',
          minValue: 50.0,
          maxValue: 900.0,
          step: 25.0,
          allowedValues: [50, 75, 100, 150, 200, 250, 300, 450, 600, 750, 900],
        ),
        CadParameter(
          id: 'port3Height',
          name: 'Part 3 Height (H3)',
          value: port3Height,
          unit: 'mm',
          minValue: 25.0,
          maxValue: 150.0,
          step: 25.0,
          allowedValues: [25, 50, 75, 100, 125, 150],
        ),
      ],
      baselineParameters: {
        'port1Width': port1Width,
        'port1Height': port1Height,
        'port2Width': port2Width,
        'port2Height': port2Height,
        'port3Width': port3Width,
        'port3Height': port3Height,
      },
    );
  }

  /// Cable Tray 90° Bend Template
  factory TemplateParameterDefinition.cableTrayBend90({
    double width = 100.0,
    double height = 50.0,
    double radius = 100.0,
  }) {
    return TemplateParameterDefinition(
      templateId: 'tray_bend_90',
      name: 'Cable Tray 90° Flat Bend',
      category: 'Tray Accessories',
      productType: 'Cable Tray 90° Bend',
      sourceDxfPath: 'assets/dxf_templates/tray_accessories/90_deg_bend_100x50.dxf',
      parameters: [
        CadParameter(
          id: 'width',
          name: 'Tray Width',
          value: width,
          unit: 'mm',
          minValue: 50.0,
          maxValue: 900.0,
          step: 25.0,
          allowedValues: [50, 75, 100, 150, 200, 300, 450, 600, 750, 900],
          description: 'Width of tray channel',
        ),
        CadParameter(
          id: 'height',
          name: 'Flange Height',
          value: height,
          unit: 'mm',
          minValue: 25.0,
          maxValue: 150.0,
          step: 25.0,
          allowedValues: [25, 50, 75, 100, 125, 150],
          description: 'Side wall height',
        ),
        CadParameter(
          id: 'radius',
          name: 'Bend Radius',
          value: radius,
          unit: 'mm',
          minValue: 50.0,
          maxValue: 600.0,
          step: 50.0,
          description: 'Inside corner turn radius',
        ),
      ],
      baselineParameters: {
        'width': width,
        'height': height,
        'radius': radius,
      },
      zoneRules: const [
        TopologicalZoneRule(
          id: 'bend_right_arm',
          type: TopologicalZoneType.rigidAnchor,
          dxFactor: 1.0,
          dyFactor: 0.0,
          drivingParamKey: 'width',
        ),
        TopologicalZoneRule(
          id: 'bend_top_arm',
          type: TopologicalZoneType.rigidAnchor,
          dxFactor: 0.0,
          dyFactor: 1.0,
          drivingParamKey: 'width',
        ),
      ],
    );
  }

  /// Cable Tray 45° Flat Bend Template
  factory TemplateParameterDefinition.cableTrayBend45({
    double width = 100.0,
    double height = 50.0,
    double radius = 100.0,
  }) {
    return TemplateParameterDefinition(
      templateId: 'tray_bend_45',
      name: 'Cable Tray 45° Flat Bend',
      category: 'Tray Accessories',
      productType: 'Cable Tray 45° Bend',
      sourceDxfPath: 'assets/dxf_templates/tray_accessories/45_deg_bend_100x50.dxf',
      parameters: [
        CadParameter(
          id: 'width',
          name: 'Tray Width',
          value: width,
          unit: 'mm',
          minValue: 50.0,
          maxValue: 900.0,
          step: 25.0,
          allowedValues: [50, 75, 100, 150, 200, 300, 450, 600, 750, 900],
        ),
        CadParameter(
          id: 'height',
          name: 'Flange Height',
          value: height,
          unit: 'mm',
          minValue: 25.0,
          maxValue: 150.0,
          step: 25.0,
          allowedValues: [25, 50, 75, 100, 125, 150],
        ),
        CadParameter(
          id: 'radius',
          name: 'Bend Radius',
          value: radius,
          unit: 'mm',
          minValue: 50.0,
          maxValue: 600.0,
          step: 50.0,
        ),
      ],
      baselineParameters: {
        'width': width,
        'height': height,
        'radius': radius,
      },
    );
  }

  /// Cable Tray Concentric / Eccentric Reducer Template
  factory TemplateParameterDefinition.cableTrayReducer({
    double widthIn = 100.0,
    double widthOut = 50.0,
    double height = 50.0,
    double length = 150.0,
  }) {
    return TemplateParameterDefinition(
      templateId: 'tray_reducer',
      name: 'Cable Tray Reducer',
      category: 'Tray Accessories',
      productType: 'Cable Tray Reducer',
      sourceDxfPath: 'assets/dxf_templates/tray_accessories/reducer_100x50x50.dxf',
      parameters: [
        CadParameter(
          id: 'widthIn',
          name: 'Input Width',
          value: widthIn,
          unit: 'mm',
          minValue: 75.0,
          maxValue: 900.0,
          step: 25.0,
          allowedValues: [75, 100, 150, 200, 300, 450, 600, 750, 900],
          description: 'Width of larger input side',
        ),
        CadParameter(
          id: 'widthOut',
          name: 'Output Width',
          value: widthOut,
          unit: 'mm',
          minValue: 50.0,
          maxValue: 750.0,
          step: 25.0,
          allowedValues: [50, 75, 100, 150, 200, 300, 450, 600, 750],
          description: 'Width of smaller output side',
        ),
        CadParameter(
          id: 'height',
          name: 'Flange Height',
          value: height,
          unit: 'mm',
          minValue: 25.0,
          maxValue: 150.0,
          step: 25.0,
          allowedValues: [25, 50, 75, 100, 125, 150],
        ),
        CadParameter(
          id: 'length',
          name: 'Transition Length',
          value: length,
          unit: 'mm',
          minValue: 100.0,
          maxValue: 500.0,
          step: 25.0,
        ),
      ],
      baselineParameters: {
        'widthIn': widthIn,
        'widthOut': widthOut,
        'height': height,
        'length': length,
      },
    );
  }

  /// Cable Tray Equal / Unequal Cross Template
  factory TemplateParameterDefinition.cableTrayCross({
    double widthMain = 100.0,
    double widthBranch = 100.0,
    double height = 50.0,
  }) {
    return TemplateParameterDefinition(
      templateId: 'tray_cross',
      name: 'Cable Tray Cross (4-Way)',
      category: 'Tray Accessories',
      productType: 'Cable Tray Cross',
      sourceDxfPath: 'assets/dxf_templates/tray_accessories/unequal_cross_100x50x100x50.dxf',
      ports: [
        TemplatePortDefinition(
          portIndex: 1,
          name: 'Main Run In (Port 1)',
          widthParamKey: 'widthMain',
          heightParamKey: 'height',
          defaultWidth: widthMain,
          defaultHeight: height,
        ),
        TemplatePortDefinition(
          portIndex: 2,
          name: 'Main Run Out (Port 2)',
          widthParamKey: 'widthMain',
          heightParamKey: 'height',
          defaultWidth: widthMain,
          defaultHeight: height,
        ),
        TemplatePortDefinition(
          portIndex: 3,
          name: 'Left Branch (Port 3)',
          widthParamKey: 'widthBranch',
          heightParamKey: 'height',
          defaultWidth: widthBranch,
          defaultHeight: height,
        ),
        TemplatePortDefinition(
          portIndex: 4,
          name: 'Right Branch (Port 4)',
          widthParamKey: 'widthBranch',
          heightParamKey: 'height',
          defaultWidth: widthBranch,
          defaultHeight: height,
        ),
      ],
      parameters: [
        CadParameter(
          id: 'widthMain',
          name: 'Main Run Width',
          value: widthMain,
          unit: 'mm',
          minValue: 50.0,
          maxValue: 900.0,
          step: 25.0,
          allowedValues: [50, 75, 100, 150, 200, 300, 450, 600, 750, 900],
        ),
        CadParameter(
          id: 'widthBranch',
          name: 'Cross Branch Width',
          value: widthBranch,
          unit: 'mm',
          minValue: 50.0,
          maxValue: 900.0,
          step: 25.0,
          allowedValues: [50, 75, 100, 150, 200, 300, 450, 600, 750, 900],
        ),
        CadParameter(
          id: 'height',
          name: 'Flange Height',
          value: height,
          unit: 'mm',
          minValue: 25.0,
          maxValue: 150.0,
          step: 25.0,
          allowedValues: [25, 50, 75, 100, 125, 150],
        ),
      ],
      baselineParameters: {
        'widthMain': widthMain,
        'widthBranch': widthBranch,
        'height': height,
      },
    );
  }

  /// Cable Tray Unequal Cross with 4 Distinct Entry Ports (W1xH1, W2xH2, W3xH3, W4xH4)
  factory TemplateParameterDefinition.cableTrayCrossUnequal({
    double port1Width = 200.0,
    double port1Height = 100.0,
    double port2Width = 150.0,
    double port2Height = 100.0,
    double port3Width = 100.0,
    double port3Height = 75.0,
    double port4Width = 50.0,
    double port4Height = 50.0,
  }) {
    return TemplateParameterDefinition(
      templateId: 'tray_unequal_cross',
      name: 'Cable Tray Unequal Cross (4 Distinct Ports)',
      category: 'Tray Accessories',
      productType: 'Cable Tray Unequal Cross',
      sourceDxfPath: 'assets/dxf_templates/tray_accessories/unequal_cross_100x50x100x50.dxf',
      ports: [
        TemplatePortDefinition(
          portIndex: 1,
          name: 'Entry Part 1 (Main In)',
          widthParamKey: 'port1Width',
          heightParamKey: 'port1Height',
          defaultWidth: port1Width,
          defaultHeight: port1Height,
        ),
        TemplatePortDefinition(
          portIndex: 2,
          name: 'Entry Part 2 (Main Out)',
          widthParamKey: 'port2Width',
          heightParamKey: 'port2Height',
          defaultWidth: port2Width,
          defaultHeight: port2Height,
        ),
        TemplatePortDefinition(
          portIndex: 3,
          name: 'Entry Part 3 (Left Branch)',
          widthParamKey: 'port3Width',
          heightParamKey: 'port3Height',
          defaultWidth: port3Width,
          defaultHeight: port3Height,
        ),
        TemplatePortDefinition(
          portIndex: 4,
          name: 'Entry Part 4 (Right Branch)',
          widthParamKey: 'port4Width',
          heightParamKey: 'port4Height',
          defaultWidth: port4Width,
          defaultHeight: port4Height,
        ),
      ],
      parameters: [
        CadParameter(
          id: 'port1Width',
          name: 'Part 1 Width (W1)',
          value: port1Width,
          unit: 'mm',
          minValue: 50.0,
          maxValue: 900.0,
          step: 25.0,
          allowedValues: [50, 75, 100, 150, 200, 250, 300, 450, 600, 750, 900],
        ),
        CadParameter(
          id: 'port1Height',
          name: 'Part 1 Height (H1)',
          value: port1Height,
          unit: 'mm',
          minValue: 25.0,
          maxValue: 150.0,
          step: 25.0,
          allowedValues: [25, 50, 75, 100, 125, 150],
        ),
        CadParameter(
          id: 'port2Width',
          name: 'Part 2 Width (W2)',
          value: port2Width,
          unit: 'mm',
          minValue: 50.0,
          maxValue: 900.0,
          step: 25.0,
          allowedValues: [50, 75, 100, 150, 200, 250, 300, 450, 600, 750, 900],
        ),
        CadParameter(
          id: 'port2Height',
          name: 'Part 2 Height (H2)',
          value: port2Height,
          unit: 'mm',
          minValue: 25.0,
          maxValue: 150.0,
          step: 25.0,
          allowedValues: [25, 50, 75, 100, 125, 150],
        ),
        CadParameter(
          id: 'port3Width',
          name: 'Part 3 Width (W3)',
          value: port3Width,
          unit: 'mm',
          minValue: 50.0,
          maxValue: 900.0,
          step: 25.0,
          allowedValues: [50, 75, 100, 150, 200, 250, 300, 450, 600, 750, 900],
        ),
        CadParameter(
          id: 'port3Height',
          name: 'Part 3 Height (H3)',
          value: port3Height,
          unit: 'mm',
          minValue: 25.0,
          maxValue: 150.0,
          step: 25.0,
          allowedValues: [25, 50, 75, 100, 125, 150],
        ),
        CadParameter(
          id: 'port4Width',
          name: 'Part 4 Width (W4)',
          value: port4Width,
          unit: 'mm',
          minValue: 50.0,
          maxValue: 900.0,
          step: 25.0,
          allowedValues: [50, 75, 100, 150, 200, 250, 300, 450, 600, 750, 900],
        ),
        CadParameter(
          id: 'port4Height',
          name: 'Part 4 Height (H4)',
          value: port4Height,
          unit: 'mm',
          minValue: 25.0,
          maxValue: 150.0,
          step: 25.0,
          allowedValues: [25, 50, 75, 100, 125, 150],
        ),
      ],
      baselineParameters: {
        'port1Width': port1Width,
        'port1Height': port1Height,
        'port2Width': port2Width,
        'port2Height': port2Height,
        'port3Width': port3Width,
        'port3Height': port3Height,
        'port4Width': port4Width,
        'port4Height': port4Height,
      },
    );
  }

  /// Cable Tray Straight Channel Blank Template
  factory TemplateParameterDefinition.cableTrayStraight({
    double width = 100.0,
    double height = 50.0,
    double length = 1000.0,
    double flange = 15.0,
  }) {
    return TemplateParameterDefinition(
      templateId: 'tray_straight',
      name: 'Straight Cable Tray Channel',
      category: 'Length',
      productType: 'Cable Tray',
      parameters: [
        CadParameter(
          id: 'width',
          name: 'Bed Width',
          value: width,
          unit: 'mm',
          minValue: 50.0,
          maxValue: 900.0,
          step: 25.0,
          allowedValues: [50, 75, 100, 150, 200, 300, 450, 600, 750, 900],
        ),
        CadParameter(
          id: 'height',
          name: 'Side Wall Height',
          value: height,
          unit: 'mm',
          minValue: 25.0,
          maxValue: 150.0,
          step: 25.0,
          allowedValues: [25, 50, 75, 100, 125, 150],
        ),
        CadParameter(
          id: 'length',
          name: 'Total Length',
          value: length,
          unit: 'mm',
          minValue: 200.0,
          maxValue: 3000.0,
          step: 100.0,
          allowedValues: [500, 1000, 1500, 2000, 2500, 3000],
        ),
        CadParameter(
          id: 'flange',
          name: 'Return Flange',
          value: flange,
          unit: 'mm',
          minValue: 10.0,
          maxValue: 25.0,
          step: 5.0,
        ),
      ],
      baselineParameters: {
        'width': width,
        'height': height,
        'length': length,
        'flange': flange,
      },
    );
  }

  /// All standard catalog templates
  static List<TemplateParameterDefinition> get standardCatalog => [
    TemplateParameterDefinition.cableTrayTee(),
    TemplateParameterDefinition.cableTrayUnequalTee(),
    TemplateParameterDefinition.cableTrayBend90(),
    TemplateParameterDefinition.cableTrayBend45(),
    TemplateParameterDefinition.cableTrayReducer(),
    TemplateParameterDefinition.cableTrayCross(),
    TemplateParameterDefinition.cableTrayCrossUnequal(),
    TemplateParameterDefinition.cableTrayStraight(),
  ];

  /// Finds a preset template by its unique template ID, or null if not found
  static TemplateParameterDefinition? findPreset(String id) {
    try {
      return standardCatalog.firstWhere((t) => t.templateId == id);
    } catch (_) {
      return null;
    }
  }
}
