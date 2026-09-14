// =============================================================================
// reference_geometry_mixin.dart
//
// Mixin for Reference & Construction Geometry management per Phase 1 Master Guide
// Sections 12, 13, 14 & Set 01.
//
// Keeps ViewModel modular by factoring out construction lines, centerlines,
// and reference edge derivation.
// =============================================================================

import 'package:flutter/foundation.dart';
import '../../models/dsf_document.dart';
import '../../models/constraints/reference_geometry.dart';
import '../../engine/constraints/reference_geometry_engine.dart';

mixin ReferenceGeometryMixin on ChangeNotifier {
  DsfDocument get document;

  final List<ReferenceGeometry> _customReferenceGeometries = [];
  bool _showConstructionGeometry = true;

  List<ReferenceGeometry> get customReferenceGeometries =>
      List.unmodifiable(_customReferenceGeometries);

  bool get showConstructionGeometry => _showConstructionGeometry;

  void toggleShowConstructionGeometry() {
    _showConstructionGeometry = !_showConstructionGeometry;
    notifyListeners();
  }

  /// All active reference geometries: derived standard edges (LEFT, RIGHT, TOP, BOTTOM, CENTER_X/Y)
  /// plus user-created construction lines.
  List<ReferenceGeometry> get allReferenceGeometries {
    if (!_showConstructionGeometry) return const [];
    final standard = ReferenceGeometryEngine.deriveStandardReferences(document);
    return [...standard, ..._customReferenceGeometries];
  }

  /// Adds a custom construction line or centerline
  void addReferenceGeometry(ReferenceGeometry ref) {
    _customReferenceGeometries.add(ref);
    notifyListeners();
  }

  /// Removes a custom construction line or centerline
  void removeReferenceGeometry(String id) {
    _customReferenceGeometries.removeWhere((r) => r.id == id);
    notifyListeners();
  }

  /// Clears all custom reference geometries
  void clearCustomReferenceGeometries() {
    _customReferenceGeometries.clear();
    notifyListeners();
  }
}
