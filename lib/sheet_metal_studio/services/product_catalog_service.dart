// =============================================================================
// product_catalog_service.dart
//
// Parses lib/sheet_metal_studio/services/product_variations.csv and provides
// structured access to Categories, Products, Variations, and Port Definitions.
// =============================================================================

import 'dart:io';

class ProductVariationItem {
  final String category;
  final String product;
  final List<String> variations;

  const ProductVariationItem({
    required this.category,
    required this.product,
    required this.variations,
  });
}

class ProductCatalogService {
  static const String defaultCsvContent = '''Category,Product,Variation 1,Variation 2,Variation 3,Variation 4,
Length,Cable Tray,Add compatments using dividers,,,,
Length,Tray Cover,Tray Cover,Ventilated Tray Cover,,,
Length,Tray Divider (for making tray compartments),,,,,
Length,Ladder,Number of rungs variations (10 rungs default),,,,
Length,Ladder Cover,,,,,
Length,Ladder Divider,,,,,
Length,Lintel,,,,,
Length,Mesh Tray (wiremesh tray),,,,,
Length,Trunking,Add compatments using dividers,,,,
Length,Trunking Cover,,,,,
Channel,B2B Channel,B2B Plain Channel,B2B Slotted Channel,,,
Channel,Channel,Plain Channel,Slotted Channel,,,
Ladder Accessories,Bend,45 Deg Bend,90 Deg Bend,,,
Ladder Accessories,Bend Cover,45 Deg Bend Cover,90 Deg Bend Cover,,,
Ladder Accessories,Inside Riser,45 Deg Inside Riser,90 Deg Inside Riser,,,
Ladder Accessories,Inside Riser Cover,45 Deg Inside Riser Cover,90 Deg Inside Riser Cover,,,
Ladder Accessories,Outside Riser,45 Deg Outside Riser,90 Deg Outside Riser,,,
Ladder Accessories,Outside Riser Cover,45 Deg Outside Riser Cover,90 Deg Outside Riser Cover,,,
Ladder Accessories,Cross,Equal Cross,Unequal Cross,,,
Ladder Accessories,Cross Cover,Equal Cross Cover,Unequal Cross Cover,,,
Ladder Accessories,Tee,Equal Tee,Unequal Tee,,,
Ladder Accessories,Tee Cover,Equal Tee Cover,Unequal Tee Cover,,,
Ladder Accessories,Reducer,Reducer (straight),Left Reducer,Right Reducer,,
Tray Accessories,Bend,45 Deg Bend,90 Deg Bend,,,
Tray Accessories,Bend Cover,45 Deg Bend Cover,90 Deg Bend Cover,,,
Tray Accessories,Inside Riser,45 Deg Inside Riser,90 Deg Inside Riser,,,
Tray Accessories,Inside Riser Cover,45 Deg Inside Riser Cover,90 Deg Inside Riser Cover,,,
Tray Accessories,Outside Riser,45 Deg Outside Riser,90 Deg Outside Riser,,,
Tray Accessories,Outside Riser Cover,45 Deg Outside Riser Cover,90 Deg Outside Riser Cover,,,
Tray Accessories,Cross,Equal Cross,Unequal Cross,,,
Tray Accessories,Cross Cover,Equal Cross Cover,Unequal Cross Cover,,,
Tray Accessories,Tee,Equal Tee,Unequal Tee,,,
Tray Accessories,Tee Cover,Equal Tee Cover,Unequal Tee Cover,,,
Tray Accessories,Reducer,Reducer (straight),Left Reducer,Right Reducer,,
Trunking Accessories,Bend,45 Deg Bend,90 Deg Bend,,,
Trunking Accessories,Bend Cover,45 Deg Bend Cover,90 Deg Bend Cover,,,
Trunking Accessories,Inside Riser,45 Deg Inside Riser,90 Deg Inside Riser,,,
Trunking Accessories,Inside Riser Cover,45 Deg Inside Riser Cover,90 Deg Inside Riser Cover,,,
Trunking Accessories,Outside Riser,45 Deg Outside Riser,90 Deg Outside Riser,,,
Trunking Accessories,Outside Riser Cover,45 Deg Outside Riser Cover,90 Deg Outside Riser Cover,,,
Trunking Accessories,Cross,Equal Cross,Unequal Cross,,,
Trunking Accessories,Cross Cover,Equal Cross Cover,Unequal Cross Cover,,,
Trunking Accessories,Tee,Equal Tee,Unequal Tee,,,
Trunking Accessories,Tee Cover,Equal Tee Cover,Unequal Tee Cover,,,
Trunking Accessories,Reducer,Reducer (straight),Left Reducer,Right Reducer,,
Coupler,Ladder Coupler,Ladder Coupler,Adjustable Ladder Coupler,,,
Coupler,Tray Coupler,Tray Coupler,Adjustable Tray Coupler (long Slots),Tray Coupler L Type,Wrap Over Coupler,
Coupler,Trunking Coupler,Trunking Coupler,Adjustable Trunking Coupler (Long Slots),,,
Coupler,Channel Coupler,,,,,
Coupler,Fishplate,,,,,
Fittings,Angle (hole variations),2 Hole L Angle,3 Hole Angle,4 Hole Angle,,
Fittings,B2B Cantilever,,,,,
Fittings,Baseplate,,,,,
Fittings,Basepost,,,,,
Fittings,Bracket,,,,,
Fittings,Cantilever,,,,,
Fittings,Cover Clamp,,,,,
Fittings,Hanger,,,,,
Fittings,Hold Down Clamp,,,,,
Fittings,Ladder Endcap,,,,,
Fittings,Lintel Bracket,,,,,
Fittings,Tray Endcap,,,,,
Fittings,Trunking Endcap,,,,,
Fittings,U Clamp,,,,,
Fittings,U Connector,,,,,
''';

  static List<ProductVariationItem>? _cachedItems;

  /// Loads and parses the CSV entries, checking the local filesystem first.
  static List<ProductVariationItem> getItems() {
    if (_cachedItems != null) return _cachedItems!;

    String csvContent = defaultCsvContent;
    try {
      const candidates = [
        'lib/sheet_metal_studio/services/product_variations.csv',
        'f:/flutter_projects/trufold_studio/lib/sheet_metal_studio/services/product_variations.csv',
      ];
      for (final p in candidates) {
        final f = File(p);
        if (f.existsSync()) {
          csvContent = f.readAsStringSync();
          break;
        }
      }
    } catch (_) {
      // Fallback to embedded CSV
    }

    final items = <ProductVariationItem>[];
    final lines = csvContent.split(RegExp(r'\r?\n'));
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty || i == 0) continue; // Skip header

      // Simple CSV split
      final parts = _parseCsvLine(line);
      if (parts.isEmpty) continue;

      final category = parts[0].trim();
      if (category.isEmpty) continue;

      final product = parts.length > 1 ? parts[1].trim() : '';
      if (product.isEmpty) continue;

      final variations = <String>[];
      for (int v = 2; v < parts.length; v++) {
        final varName = parts[v].trim();
        if (varName.isNotEmpty && !variations.contains(varName)) {
          variations.add(varName);
        }
      }

      items.add(ProductVariationItem(
        category: category,
        product: product,
        variations: variations,
      ));
    }

    _cachedItems = items;
    return items;
  }

  static List<String> _parseCsvLine(String line) {
    final result = <String>[];
    final buffer = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        result.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    result.add(buffer.toString());
    return result;
  }

  /// Returns all unique category names (e.g. Length, Tray Accessories, Coupler, Fittings, None)
  static List<String> getCategories() {
    final items = getItems();
    final set = <String>{'None'};
    for (final it in items) {
      set.add(it.category);
    }
    return set.toList();
  }

  /// Returns all products belonging to a category
  static List<String> getProductsForCategory(String category) {
    if (category == 'None') {
      final items = getItems();
      final set = <String>{'None'};
      for (final it in items) {
        set.add(it.product);
      }
      return set.toList();
    }
    final items = getItems().where((it) => it.category == category).toList();
    final set = <String>{'None'};
    for (final it in items) {
      set.add(it.product);
    }
    return set.toList();
  }

  /// Returns all variations for a given product under a category
  static List<String> getVariations(String category, String product) {
    if (product == 'None') return ['None'];

    final matches = getItems().where((it) {
      if (category != 'None' && it.category != category) return false;
      return it.product.toLowerCase() == product.toLowerCase();
    }).toList();

    final vars = <String>{'None'};
    for (final m in matches) {
      vars.addAll(m.variations);
    }

    // If no specific variation listed in CSV, add default "Standard"
    if (vars.length == 1) {
      vars.add('Standard');
    }

    return vars.toList();
  }

  /// Determines how many ports a fitting has based on its product name & variation
  static int getPortCount([String? product, String? variation]) {
    final pLower = (product ?? '').toLowerCase();
    final vLower = (variation ?? '').toLowerCase();

    if (pLower.contains('tee') || vLower.contains('tee')) {
      return 3;
    }
    if (pLower.contains('cross') || vLower.contains('cross')) {
      return 4;
    }
    if (pLower.contains('reducer')) {
      return 2;
    }
    if (pLower.contains('bend') || pLower.contains('riser') || pLower.contains('tray') || pLower.contains('trunking')) {
      return 2;
    }
    if (pLower.contains('coupler') || pLower.contains('cover') || pLower.contains('divider')) {
      return 2;
    }
    return 2; // Default for channel fittings
  }
}
