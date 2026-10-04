// =============================================================================
// dxf_fitting_metadata.dart
//
// Metadata model, catalog registry, and serialization for sheet metal fittings
// (Cable Tray Accessories, Trunking Accessories, Covers, Risers, Reducers, etc.)
// Attaches category, product, and variant parameters to DSF documents.
// =============================================================================

import 'cad_primitives.dart';
import 'dsf_document.dart';
import '../engine/fitting_port_annotation_engine.dart';
import '../services/product_catalog_service.dart';

/// Standard accessory categories in commercial cable management
class FittingCategory {
  static const String none = 'None';
  static const String trayAccessories = 'Tray Accessories';
  static const String trunkingAccessories = 'Trunking Accessories';
  static const String ladderAccessories = 'Ladder Accessories';
  static const String channel = 'Channel';
  static const String length = 'Length';
  static const String coupler = 'Coupler';
  static const String fittings = 'Fittings';

  // Backwards compatibility aliases
  static const String cableTrayAccessories = 'Tray Accessories';
  static const String cableTrayCovers = 'Tray Accessories';
  static const String trunkingCovers = 'Trunking Accessories';

  static List<String> get all {
    final fromCsv = ProductCatalogService.getCategories();
    final list = fromCsv.toList();
    list.remove('None');
    return ['None', ...list];
  }
}

/// Recognized product types in Danish Sheet Fold & CAD Fittings
class FittingProductType {
  static const String none = 'None';
  static const String bend = 'Bend';
  static const String bendCover = 'Bend Cover';
  static const String insideRiser = 'Inside Riser';
  static const String insideRiserCover = 'Inside Riser Cover';
  static const String outsideRiser = 'Outside Riser';
  static const String outsideRiserCover = 'Outside Riser Cover';
  static const String cross = 'Cross';
  static const String crossCover = 'Cross Cover';
  static const String tee = 'Tee';
  static const String teeCover = 'Tee Cover';
  static const String reducer = 'Reducer';
  static const String genericFitting = 'Sheet Metal Fitting';

  // Backwards compatibility aliases
  static const String unequalTee = 'Unequal Tee';
  static const String equalTee = 'Equal Tee';
  static const String unequalCross = 'Unequal Cross';
  static const String equalCross = 'Equal Cross';
  static const String bend90 = '90° Flat Bend';
  static const String bend45 = '45° Flat Bend';
  static const String insideRiser90 = '90° Inside Riser';
  static const String insideRiser45 = '45° Inside Riser';
  static const String outsideRiser90 = '90° Outside Riser';
  static const String outsideRiser45 = '45° Outside Riser';

  static const List<String> all = [
    none,
    bend,
    bendCover,
    insideRiser,
    insideRiserCover,
    outsideRiser,
    outsideRiserCover,
    cross,
    crossCover,
    tee,
    teeCover,
    reducer,
    genericFitting,
  ];
}

/// A standard catalog product variant specification
class FittingVariant {
  final String id;
  final String name; // e.g. "100x50x100x50"
  final String category;
  final String product;
  final Map<String, double> parameters;
  final double flangeMm;

  const FittingVariant({
    required this.id,
    required this.name,
    required this.category,
    required this.product,
    required this.parameters,
    this.flangeMm = 13.0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'product': product,
        'parameters': parameters,
        'flangeMm': flangeMm,
      };

  factory FittingVariant.fromJson(Map<String, dynamic> json) => FittingVariant(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        category: json['category'] as String? ?? FittingCategory.none,
        product: json['product'] as String? ?? FittingProductType.none,
        parameters: (json['parameters'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, (v as num).toDouble())),
        flangeMm: (json['flangeMm'] as num?)?.toDouble() ?? 13.0,
      );
}

/// Active fitting metadata attached to a DSF drawing
class DxfFittingMetadata {
  final String category;
  final String product;
  final String variantName;
  final double flangeMm;
  final Map<String, double> parameters;
  final Map<String, double> analyzedDimensions;
  final Map<String, String>? portAssignments;
  final Map<String, Map<String, dynamic>>? manualPortEdges;
  final Map<String, List<double>>? portBadgeOffsets;
  final Map<String, Map<String, dynamic>>? semanticPorts;

  const DxfFittingMetadata({
    this.category = FittingCategory.none,
    this.product = FittingProductType.none,
    this.variantName = 'None',
    this.flangeMm = 13.0,
    this.parameters = const {},
    this.analyzedDimensions = const {},
    this.portAssignments,
    this.manualPortEdges,
    this.portBadgeOffsets,
    this.semanticPorts,
  });

  bool get isAssigned =>
      category != FittingCategory.none && product != FittingProductType.none;

  bool get isUnequalTee =>
      (product.toLowerCase().contains('tee') && variantName.toLowerCase().contains('unequal')) ||
      product.toLowerCase() == 'unequal tee' ||
      (product.toLowerCase().contains('tee') && parameters.containsKey('port3Width'));

  bool get isEqualTee =>
      (product.toLowerCase().contains('tee') && !variantName.toLowerCase().contains('unequal') && !parameters.containsKey('port3Width')) ||
      product.toLowerCase() == 'equal tee';

  bool get isUnequalCross =>
      (product.toLowerCase().contains('cross') && variantName.toLowerCase().contains('unequal')) ||
      product.toLowerCase() == 'unequal cross' ||
      (product.toLowerCase().contains('cross') && parameters.containsKey('port4Width'));

  bool get isEqualCross =>
      (product.toLowerCase().contains('cross') && !variantName.toLowerCase().contains('unequal') && !parameters.containsKey('port4Width')) ||
      product.toLowerCase() == 'equal cross';

  bool get isBend =>
      product.toLowerCase().contains('bend');

  bool get isRiser =>
      product.toLowerCase().contains('riser');

  bool get isReducer =>
      product.toLowerCase().contains('reducer');

  bool get isLadder =>
      category.toLowerCase().contains('ladder') ||
      product.toLowerCase().contains('ladder') ||
      variantName.toLowerCase().contains('ladder');

  /// Detects all channel port openings on the outer contour and maps dimensions.
  /// If [onlyAssigned] is true, returns only openings that have been assigned by the user in [manualPortEdges].
  List<ProductPortOpening> getPortOpenings(DsfDocument doc, {bool onlyAssigned = false}) {
    final list = FittingPortAnnotationEngine.detectPortOpenings(document: doc, metadata: this);
    if (manualPortEdges == null || manualPortEdges!.isEmpty) {
      if (onlyAssigned) return const [];
      return list;
    }

    final result = <ProductPortOpening>[];
    final handledPortIds = <String>{};

    for (final port in list) {
      final manual = manualPortEdges![port.id];
      if (manual != null && manual.containsKey('widthEdge')) {
        try {
          final wEdge = manual['widthEdge'] as Map;
          final p1List = (wEdge['p1'] as List).map((n) => (n as num).toDouble()).toList();
          final p2List = (wEdge['p2'] as List).map((n) => (n as num).toDouble()).toList();
          final p1 = CadPoint2D(p1List[0], p1List[1]);
          final p2 = CadPoint2D(p2List[0], p2List[1]);
          final c = CadPoint2D((p1.x + p2.x) / 2.0, (p1.y + p2.y) / 2.0);
          final len = p1.distanceTo(p2);

          final dx = p2.x - p1.x;
          final dy = p2.y - p1.y;
          CadPoint2D norm = port.normal;
          if (len > 1e-4) {
            final n1 = CadPoint2D(-dy / len, dx / len);
            final n2 = CadPoint2D(dy / len, -dx / len);
            final center = doc.outerContour.isNotEmpty
                ? CadPoint2D(
                    doc.outerContour.map((p) => p.x).reduce((a, b) => a + b) / doc.outerContour.length,
                    doc.outerContour.map((p) => p.y).reduce((a, b) => a + b) / doc.outerContour.length,
                  )
                : const CadPoint2D(0, 0);
            final d1 = (c.x + n1.x * 10 - center.x) * (c.x + n1.x * 10 - center.x) +
                (c.y + n1.y * 10 - center.y) * (c.y + n1.y * 10 - center.y);
            final d2 = (c.x + n2.x * 10 - center.x) * (c.x + n2.x * 10 - center.x) +
                (c.y + n2.y * 10 - center.y) * (c.y + n2.y * 10 - center.y);
            norm = d1 > d2 ? n1 : n2;
          }

          final sideName = manual['side'] as String? ?? portAssignments?[port.id] ?? port.side.name;
          final side = PortSide.fromString(sideName);

          final wVal = parameters['${port.id}Width'] ??
              (port.id == 'entry'
                  ? parameters['widthIn']
                  : (port.id == 'exit'
                      ? parameters['widthOut']
                      : (parameters['width'] ?? len))) ?? len;
          final hVal = parameters['${port.id}Height'] ??
              (parameters['height'] ?? port.heightMm);

          result.add(ProductPortOpening(
            id: port.id,
            label: port.label,
            widthMm: wVal,
            heightMm: hVal,
            edgeP1: p1,
            edgeP2: p2,
            center: c,
            normal: norm,
            measuredLengthMm: len,
            side: side,
          ));
          handledPortIds.add(port.id);
          continue;
        } catch (_) {}
      }
      if (!onlyAssigned) {
        result.add(port);
      }
    }

    // Also include any manual port assignments that were not detected by the heuristic
    for (final entry in manualPortEdges!.entries) {
      final portId = entry.key;
      if (handledPortIds.contains(portId)) continue;
      final manual = entry.value;
      if (manual.containsKey('widthEdge')) {
        try {
          final wEdge = manual['widthEdge'] as Map;
          final p1List = (wEdge['p1'] as List).map((n) => (n as num).toDouble()).toList();
          final p2List = (wEdge['p2'] as List).map((n) => (n as num).toDouble()).toList();
          final p1 = CadPoint2D(p1List[0], p1List[1]);
          final p2 = CadPoint2D(p2List[0], p2List[1]);
          final c = CadPoint2D((p1.x + p2.x) / 2.0, (p1.y + p2.y) / 2.0);
          final len = p1.distanceTo(p2);

          final dx = p2.x - p1.x;
          final dy = p2.y - p1.y;
          CadPoint2D norm = const CadPoint2D(0, 1);
          if (len > 1e-4) {
            final n1 = CadPoint2D(-dy / len, dx / len);
            final n2 = CadPoint2D(dy / len, -dx / len);
            final center = doc.outerContour.isNotEmpty
                ? CadPoint2D(
                    doc.outerContour.map((p) => p.x).reduce((a, b) => a + b) / doc.outerContour.length,
                    doc.outerContour.map((p) => p.y).reduce((a, b) => a + b) / doc.outerContour.length,
                  )
                : const CadPoint2D(0, 0);
            final d1 = (c.x + n1.x * 10 - center.x) * (c.x + n1.x * 10 - center.x) +
                (c.y + n1.y * 10 - center.y) * (c.y + n1.y * 10 - center.y);
            final d2 = (c.x + n2.x * 10 - center.x) * (c.x + n2.x * 10 - center.x) +
                (c.y + n2.y * 10 - center.y) * (c.y + n2.y * 10 - center.y);
            norm = d1 > d2 ? n1 : n2;
          }

          final portNum = portId.replaceAll('port', '');
          final portLabel = portId == 'port1' ? 'Port 1 (Inlet)' : (portId == 'port2' ? 'Port 2 (Outlet)' : 'Port $portNum');
          final sideName = manual['side'] as String? ?? portAssignments?[portId] ?? 'bottom';
          final side = PortSide.fromString(sideName);

          final wVal = parameters['${portId}Width'] ?? (parameters['width'] ?? len);
          final hVal = parameters['${portId}Height'] ?? (parameters['height'] ?? 50.0);

          result.add(ProductPortOpening(
            id: portId,
            label: portLabel,
            widthMm: wVal,
            heightMm: hVal,
            edgeP1: p1,
            edgeP2: p2,
            center: c,
            normal: norm,
            measuredLengthMm: len,
            side: side,
          ));
        } catch (_) {}
      }
    }

    return result;
  }

  DxfFittingMetadata copyWith({
    String? category,
    String? product,
    String? variantName,
    double? flangeMm,
    Map<String, double>? parameters,
    Map<String, double>? analyzedDimensions,
    Map<String, String>? portAssignments,
    Map<String, Map<String, dynamic>>? manualPortEdges,
    Map<String, List<double>>? portBadgeOffsets,
    Map<String, Map<String, dynamic>>? semanticPorts,
  }) {
    return DxfFittingMetadata(
      category: category ?? this.category,
      product: product ?? this.product,
      variantName: variantName ?? this.variantName,
      flangeMm: flangeMm ?? this.flangeMm,
      parameters: parameters ?? Map.from(this.parameters),
      analyzedDimensions: analyzedDimensions ?? Map.from(this.analyzedDimensions),
      portAssignments: portAssignments ?? (this.portAssignments != null ? Map.from(this.portAssignments!) : null),
      manualPortEdges: manualPortEdges ?? (this.manualPortEdges != null ? Map.from(this.manualPortEdges!) : null),
      portBadgeOffsets: portBadgeOffsets ?? (this.portBadgeOffsets != null ? Map.from(this.portBadgeOffsets!) : null),
      semanticPorts: semanticPorts ?? (this.semanticPorts != null ? Map.from(this.semanticPorts!) : null),
    );
  }

  Map<String, dynamic> toJson() => {
        'category': category,
        'product': product,
        'variantName': variantName,
        'flangeMm': flangeMm,
        'parameters': parameters,
        'analyzedDimensions': analyzedDimensions,
        if (portAssignments != null) 'portAssignments': portAssignments,
        if (manualPortEdges != null) 'manualPortEdges': manualPortEdges,
        if (portBadgeOffsets != null) 'portBadgeOffsets': portBadgeOffsets,
        if (semanticPorts != null) 'semanticPorts': semanticPorts,
      };

  factory DxfFittingMetadata.fromJson(Map<String, dynamic> json) {
    Map<String, Map<String, dynamic>>? manualEdges;
    if (json['manualPortEdges'] is Map) {
      manualEdges = {};
      (json['manualPortEdges'] as Map).forEach((k, v) {
        if (v is Map) {
          manualEdges![k.toString()] = Map<String, dynamic>.from(v);
        }
      });
    }

    Map<String, List<double>>? badgeOffsets;
    if (json['portBadgeOffsets'] is Map) {
      badgeOffsets = {};
      (json['portBadgeOffsets'] as Map).forEach((k, v) {
        if (v is List) {
          badgeOffsets![k.toString()] = v.map((n) => (n as num).toDouble()).toList();
        }
      });
    }

    Map<String, Map<String, dynamic>>? semantic;
    if (json['semanticPorts'] is Map) {
      semantic = {};
      (json['semanticPorts'] as Map).forEach((k, v) {
        if (v is Map) {
          semantic![k.toString()] = Map<String, dynamic>.from(v);
        }
      });
    }

    return DxfFittingMetadata(
      category: json['category'] as String? ?? FittingCategory.none,
      product: json['product'] as String? ?? FittingProductType.none,
      variantName: json['variantName'] as String? ?? 'None',
      flangeMm: (json['flangeMm'] as num?)?.toDouble() ?? 13.0,
      parameters: (json['parameters'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, (v as num).toDouble())),
      analyzedDimensions:
          (json['analyzedDimensions'] as Map<String, dynamic>? ?? {})
              .map((k, v) => MapEntry(k, (v as num).toDouble())),
      portAssignments: (json['portAssignments'] as Map?)?.map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      ),
      manualPortEdges: manualEdges,
      portBadgeOffsets: badgeOffsets,
      semanticPorts: semantic,
    );
  }

  /// Extracts fitting metadata stored in a DSF document
  static DxfFittingMetadata? fromDocument(DsfDocument doc) {
    DxfFittingMetadata? result;
    final meta = doc.metadata['fittingMetadata'];
    if (meta is Map<String, dynamic>) {
      result = DxfFittingMetadata.fromJson(meta);
    } else if (meta is Map) {
      result = DxfFittingMetadata.fromJson(Map<String, dynamic>.from(meta));
    }

    final docCat = doc.category;
    if (result != null) {
      if ((result.category == FittingCategory.none || result.category.isEmpty) && docCat.isNotEmpty) {
        result = result.copyWith(category: docCat);
      }
      if (result.product == FittingProductType.reducer) {
        final alignVal = doc.parameters['reducer_alignment'] ??
            (doc.metadata['reducer_alignment'] as num?)?.toDouble() ??
            (doc.metadata['cms_param_reducer_alignment'] as num?)?.toDouble();
        if (alignVal == 1.0) {
          result = result.copyWith(variantName: 'Left Reducer');
        } else if (alignVal == 2.0) {
          result = result.copyWith(variantName: 'Right Reducer');
        } else if (alignVal == 0.0) {
          result = result.copyWith(variantName: 'Reducer (straight)');
        }
      }
      return result;
    }

    // Auto-detect from filename and geometry if not explicitly saved
    return detectFromDocument(doc);
  }

  /// Automatically recognizes fitting category, product, and dimensions
  /// from the document's productType, itemName, or outer contour geometry.
  static DxfFittingMetadata detectFromDocument(DsfDocument doc, {String? fileName}) {
    final name = (fileName ?? (doc.itemName.isNotEmpty ? doc.itemName : doc.productType))
        .toLowerCase();

    final isExplicitPlateOrBlank = name.contains('plate') || name.contains('blank');
    final hasFittingKeyword = !isExplicitPlateOrBlank &&
        (name.contains('tray') ||
            name.contains('trunking') ||
            name.contains('ladder') ||
            name.contains('channel') ||
            name.contains('length') ||
            name.contains('coupler') ||
            name.contains('fitting') ||
            name.contains('bend') ||
            name.contains('tee') ||
            name.contains('cross') ||
            name.contains('riser') ||
            name.contains('reducer') ||
            RegExp(r'\d+x\d+').hasMatch(name) ||
            RegExp(r'^(45|90)_').hasMatch(name));

    if (!hasFittingKeyword) {
      return const DxfFittingMetadata(
        category: FittingCategory.none,
        product: FittingProductType.none,
        variantName: 'None',
        flangeMm: 13.0,
      );
    }

    String category = FittingCategory.trayAccessories;
    final docCat = doc.category;
    final isLadder = name.contains('ladder') ||
        doc.productType == 'cable_ladder' ||
        (doc.metadata['isLadderAssembly'] == true);

    if (docCat.isNotEmpty && docCat != FittingCategory.none) {
      category = docCat;
    } else if (isLadder) {
      final isStraight = name.contains('straight') ||
          name.contains('length') ||
          (!name.contains('bend') &&
              !name.contains('riser') &&
              !name.contains('tee') &&
              !name.contains('cross') &&
              !name.contains('reducer'));
      category = isStraight ? FittingCategory.length : FittingCategory.ladderAccessories;
    } else if (name.contains('trunking')) {
      category = FittingCategory.trunkingAccessories;
    } else if (name.contains('channel')) {
      category = FittingCategory.channel;
    } else if (name.contains('length') || name.contains('straight')) {
      category = FittingCategory.length;
    } else if (name.contains('coupler')) {
      category = FittingCategory.coupler;
    } else if (name.contains('fitting')) {
      category = FittingCategory.fittings;
    } else {
      category = FittingCategory.trayAccessories;
    }

    String product = FittingProductType.bend;
    String variantName = '90 Deg Bend';

    if (isLadder &&
        (name.contains('straight') ||
            name.contains('length') ||
            (!name.contains('bend') &&
                !name.contains('riser') &&
                !name.contains('tee') &&
                !name.contains('cross') &&
                !name.contains('reducer')))) {
      product = 'Ladder';
      variantName = doc.metadata['fittingVariant'] as String? ?? 'Cable Ladder Straight Length';
    } else if (name.contains('bend') && name.contains('cover')) {
      product = FittingProductType.bendCover;
      variantName = name.contains('45') ? '45 Deg Bend Cover' : '90 Deg Bend Cover';
    } else if (name.contains('bend')) {
      product = FittingProductType.bend;
      variantName = name.contains('45') ? '45 Deg Bend' : '90 Deg Bend';
    } else if ((name.contains('inside') || name.contains('in_riser')) && name.contains('riser') && name.contains('cover')) {
      product = FittingProductType.insideRiserCover;
      variantName = name.contains('45') ? '45 Deg Inside Riser Cover' : '90 Deg Inside Riser Cover';
    } else if ((name.contains('inside') || name.contains('in_riser')) && name.contains('riser')) {
      product = FittingProductType.insideRiser;
      variantName = name.contains('45') ? '45 Deg Inside Riser' : '90 Deg Inside Riser';
    } else if ((name.contains('outside') || name.contains('out_riser')) && name.contains('riser') && name.contains('cover')) {
      product = FittingProductType.outsideRiserCover;
      variantName = name.contains('45') ? '45 Deg Outside Riser Cover' : '90 Deg Outside Riser Cover';
    } else if ((name.contains('outside') || name.contains('out_riser')) && name.contains('riser')) {
      product = FittingProductType.outsideRiser;
      variantName = name.contains('45') ? '45 Deg Outside Riser' : '90 Deg Outside Riser';
    } else if (name.contains('cross') && name.contains('cover')) {
      product = FittingProductType.crossCover;
      variantName = name.contains('unequal') ? 'Unequal Cross Cover' : 'Equal Cross Cover';
    } else if (name.contains('cross')) {
      product = FittingProductType.cross;
      variantName = name.contains('unequal') ? 'Unequal Cross' : 'Equal Cross';
    } else if (name.contains('tee') && name.contains('cover')) {
      product = FittingProductType.teeCover;
      variantName = name.contains('unequal') ? 'Unequal Tee Cover' : 'Equal Tee Cover';
    } else if (name.contains('tee')) {
      product = FittingProductType.tee;
      variantName = name.contains('unequal') ? 'Unequal Tee' : 'Equal Tee';
    } else if (name.contains('reducer')) {
      product = FittingProductType.reducer;
      final alignVal = doc.parameters['reducer_alignment'] ??
          (doc.metadata['reducer_alignment'] as num?)?.toDouble() ??
          (doc.metadata['cms_param_reducer_alignment'] as num?)?.toDouble();
      if (alignVal == 1.0 || name.contains('left')) {
        variantName = 'Left Reducer';
      } else if (alignVal == 2.0 || name.contains('right')) {
        variantName = 'Right Reducer';
      } else {
        variantName = 'Reducer (straight)';
      }
    } else if (name.contains('channel')) {
      product = 'Channel';
      variantName = name.contains('slotted') ? 'Slotted Channel' : 'Plain Channel';
    } else if (name.contains('length') || name.contains('straight')) {
      product = 'Length';
      variantName = 'Straight Length';
    } else {
      product = FittingProductType.genericFitting;
      variantName = doc.itemName.isNotEmpty ? doc.itemName : 'Sheet Metal Part';
    }

    // Extract numerical dimensions from filename if present (e.g. 100x50 or 45_deg_bend_100x50)
    final xMatch = RegExp(r'\b(\d+(?:x\d+)+)\b').firstMatch(name);
    List<double> numbers;
    if (xMatch != null) {
      numbers = xMatch.group(1)!
          .split('x')
          .map((s) => double.tryParse(s) ?? 0.0)
          .where((v) => v >= 10.0)
          .toList();
    } else {
      final rawNumbers = RegExp(r'\d+')
          .allMatches(name)
          .map((m) => double.tryParse(m.group(0)!) ?? 0.0)
          .where((v) => v >= 10.0)
          .toList();
      if ((name.contains('45') || name.contains('90')) &&
          (name.contains('bend') || name.contains('riser')) &&
          rawNumbers.isNotEmpty &&
          (rawNumbers.first == 45.0 || rawNumbers.first == 90.0)) {
        rawNumbers.removeAt(0);
      }
      numbers = rawNumbers;
    }

    var dimNumbers = List<double>.from(numbers);
    if (product == FittingProductType.bend ||
        product == FittingProductType.bendCover ||
        product == FittingProductType.insideRiser ||
        product == FittingProductType.insideRiserCover ||
        product == FittingProductType.outsideRiser ||
        product == FittingProductType.outsideRiserCover) {
      if (dimNumbers.length < 2) dimNumbers = [100.0, 50.0];
    } else if (product == FittingProductType.tee || product == FittingProductType.teeCover) {
      if (dimNumbers.length < 2) dimNumbers = [100.0, 50.0, 100.0, 50.0, 100.0, 50.0];
    } else if (product == FittingProductType.cross || product == FittingProductType.crossCover) {
      if (dimNumbers.length < 2) dimNumbers = [100.0, 50.0, 100.0, 50.0, 100.0, 50.0, 100.0, 50.0];
    }

    final params = <String, double>{};
    double flange = 10.0;

    // Analyze geometric bounds and tab depth
    final analyzed = _analyzeContourGeometry(doc.outerContour);
    if (analyzed['detectedFlangeMm'] != null && analyzed['detectedFlangeMm']! >= 7.0) {
      flange = analyzed['detectedFlangeMm']!;
    }

    if (product == FittingProductType.tee) {
      final isUnequal = name.contains('unequal') ||
          dimNumbers.length > 2 ||
          (analyzed['branchWidth'] != null &&
              analyzed['bedWidth'] != null &&
              (analyzed['branchWidth']! - analyzed['bedWidth']!).abs() > 5.0);
      variantName = isUnequal ? 'Unequal Tee' : 'Equal Tee';
      if (isUnequal) {
        params['isLinkedPorts'] = 0.0;
        params['port1Width'] = dimNumbers.isNotEmpty ? dimNumbers[0] : (analyzed['bedWidth'] ?? 100.0);
        params['port1Height'] = dimNumbers.length > 1 ? dimNumbers[1] : 50.0;
        params['port2Width'] = dimNumbers.length > 2 ? dimNumbers[2] : (analyzed['bedWidth'] ?? 100.0);
        params['port2Height'] = dimNumbers.length > 3 ? dimNumbers[3] : (dimNumbers.length > 1 ? dimNumbers[1] : 50.0);
        params['port3Width'] = dimNumbers.length > 4 ? dimNumbers[4] : (analyzed['branchWidth'] ?? 100.0);
        params['port3Height'] = dimNumbers.length > 5 ? dimNumbers[5] : (dimNumbers.length > 1 ? dimNumbers[1] : 50.0);
        params['width'] = params['port1Width']!;
        params['height'] = params['port1Height']!;
        params['branchWidth'] = params['port3Width']!;
      } else {
        params['isLinkedPorts'] = 1.0;
        final w = dimNumbers.isNotEmpty ? dimNumbers[0] : (analyzed['bedWidth'] ?? 100.0);
        final h = dimNumbers.length > 1 ? dimNumbers[1] : 50.0;
        params['width'] = w;
        params['branchWidth'] = w;
        params['height'] = h;
        params['port1Width'] = w;
        params['port1Height'] = h;
        params['port2Width'] = w;
        params['port2Height'] = h;
        params['port3Width'] = w;
        params['port3Height'] = h;
      }
    } else if (product == FittingProductType.cross) {
      final isUnequal = name.contains('unequal') || dimNumbers.length > 2;
      variantName = isUnequal ? 'Unequal Cross' : 'Equal Cross';
      if (isUnequal) {
        params['isLinkedPorts'] = 0.0;
        params['port1Width'] = dimNumbers.isNotEmpty ? dimNumbers[0] : 100.0;
        params['port1Height'] = dimNumbers.length > 1 ? dimNumbers[1] : 50.0;
        params['port2Width'] = dimNumbers.length > 2 ? dimNumbers[2] : 100.0;
        params['port2Height'] = dimNumbers.length > 3 ? dimNumbers[3] : 50.0;
        params['port3Width'] = dimNumbers.length > 4 ? dimNumbers[4] : 100.0;
        params['port3Height'] = dimNumbers.length > 5 ? dimNumbers[5] : 50.0;
        params['port4Width'] = dimNumbers.length > 6 ? dimNumbers[6] : 100.0;
        params['port4Height'] = dimNumbers.length > 7 ? dimNumbers[7] : 50.0;
        params['width'] = params['port1Width']!;
        params['height'] = params['port1Height']!;
      } else {
        params['isLinkedPorts'] = 1.0;
        final w = dimNumbers.isNotEmpty ? dimNumbers[0] : 100.0;
        final h = dimNumbers.length > 1 ? dimNumbers[1] : 50.0;
        params['width'] = w;
        params['height'] = h;
        params['port1Width'] = w;
        params['port1Height'] = h;
        params['port2Width'] = w;
        params['port2Height'] = h;
        params['port3Width'] = w;
        params['port3Height'] = h;
        params['port4Width'] = w;
        params['port4Height'] = h;
      }
    } else if (product == FittingProductType.bend || product == FittingProductType.bendCover ||
               product == FittingProductType.insideRiser || product == FittingProductType.insideRiserCover ||
               product == FittingProductType.outsideRiser || product == FittingProductType.outsideRiserCover) {
      final w = dimNumbers.isNotEmpty ? dimNumbers[0] : (analyzed['bedWidth'] ?? 100.0);
      final h = dimNumbers.length > 1 ? dimNumbers[1] : 50.0;
      params['width'] = w;
      params['height'] = h;
      params['port1Width'] = w;
      params['port1Height'] = h;
      params['port2Width'] = w;
      params['port2Height'] = h;
      params['angle'] = variantName.contains('45') ? 45.0 : 90.0;
    } else if (product == FittingProductType.reducer) {
      final wIn = dimNumbers.isNotEmpty ? dimNumbers[0] : 100.0;
      final wOut = dimNumbers.length > 1 ? dimNumbers[1] : 50.0;
      final h = dimNumbers.length > 2 ? dimNumbers[2] : 50.0;
      params['widthIn'] = wIn;
      params['widthOut'] = wOut;
      params['height'] = h;
      params['port1Width'] = wIn;
      params['port1Height'] = h;
      params['port2Width'] = wOut;
      params['port2Height'] = h;
    } else {
      final w = dimNumbers.isNotEmpty ? dimNumbers[0] : 100.0;
      final h = dimNumbers.length > 1 ? dimNumbers[1] : 50.0;
      params['width'] = w;
      params['height'] = h;
      params['port1Width'] = w;
      params['port1Height'] = h;
      params['port2Width'] = w;
      params['port2Height'] = h;
    }

    return DxfFittingMetadata(
      category: category,
      product: product,
      variantName: variantName,
      flangeMm: flange,
      parameters: params,
      analyzedDimensions: analyzed,
    );
  }

  static Map<String, double> _analyzeContourGeometry(List<CadPoint2D> contour) {
    if (contour.length < 3) return {};

    double minX = contour.first.x, maxX = contour.first.x;
    double minY = contour.first.y, maxY = contour.first.y;
    for (final p in contour) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }

    final overallWidth = maxX - minX;
    final overallHeight = maxY - minY;

    double? detectedFlange;
    final detectedTabWidths = <double>[];
    final n = contour.length;

    for (int i = 0; i < n; i++) {
      final p1 = contour[i];
      final p2 = contour[(i + 1) % n];
      final len = p1.distanceTo(p2);
      if (len >= 7.0 && len <= 25.0) {
        detectedFlange ??= len;
        // Check if adjacent segment is a tab edge bounded by another short side
        final p3 = contour[(i + 2) % n];
        final p4 = contour[(i + 3) % n];
        final lenEdge = p2.distanceTo(p3);
        final lenOppSide = p3.distanceTo(p4);
        if (lenEdge >= 20.0 && lenOppSide >= 7.0 && lenOppSide <= 25.0) {
          detectedTabWidths.add(lenEdge);
        }
      }
    }

    final map = <String, double>{
      'overallWidth': overallWidth,
      'overallHeight': overallHeight,
    };
    if (detectedFlange != null) {
      map['detectedFlangeMm'] = detectedFlange;
    }
    if (detectedTabWidths.isNotEmpty) {
      detectedTabWidths.sort((a, b) => b.compareTo(a)); // descending
      map['bedWidth'] = detectedTabWidths.first;
      map['port1Width'] = detectedTabWidths.first;
      map['port2Width'] = detectedTabWidths.length > 1 ? detectedTabWidths[1] : detectedTabWidths.first;
      map['port3Width'] = detectedTabWidths.last;
      map['branchWidth'] = detectedTabWidths.last;
      map['detectedPortWidthMm'] = detectedTabWidths.first;
      map['detectedBranchWidthMm'] = detectedTabWidths.last;
    }
    return map;
  }
}

/// Catalog Registry providing searchable categories, products, and variants
class FittingCatalogRegistry {
  static List<String> getCategories() {
    return ProductCatalogService.getCategories();
  }

  static List<String> getProductsForCategory(String category) {
    return ProductCatalogService.getProductsForCategory(category);
  }

  static List<String> getVariantNamesForProduct(String category, String product) {
    return ProductCatalogService.getVariations(category, product);
  }

  static List<FittingVariant> getVariantsForProduct(String category, String product) {
    final names = getVariantNamesForProduct(category, product);
    return names.where((n) => n != 'None').map((varName) {
      final angle = varName.contains('45') ? 45.0 : (varName.contains('90') ? 90.0 : null);
      final params = <String, double>{};
      if (angle != null) params['angle'] = angle;
      return FittingVariant(
        id: '${category}_${product}_$varName'.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_'),
        name: varName,
        category: category,
        product: product,
        flangeMm: 13.0,
        parameters: params,
      );
    }).toList();
  }
}
