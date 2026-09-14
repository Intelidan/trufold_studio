// =============================================================================
// constraint_viewmodel_mixin.dart
//
// Mixin for Geometric & Dimensional Constraints per Phase 1 Master Guide
// Sections 6, 7, 8, 10, 11, 15, 17, 49 & Sets 03, 04, 05, 06, 07.
//
// Manages:
// - Constraint Definitions (driving vs reference, parameter links)
// - Interactive 2-click constraint creation HUD workflow
// - Conflict detection & state reporting (Solved, Over-constrained, Conflict)
// - Execution of GeometricConstraintSolver
// =============================================================================

import 'package:flutter/foundation.dart';
import '../../models/cad_constraint.dart';
import '../../models/dsf_document.dart';
import '../../models/constraints/stable_geometry_reference.dart';
import '../../models/constraints/constraint_definition.dart';
import '../../models/constraints/reference_geometry.dart';
import '../../engine/constraints/geometric_constraint_solver.dart';
import '../../engine/constraints/reference_geometry_engine.dart';

mixin ConstraintViewModelMixin on ChangeNotifier {
  DsfDocument get document;
  void recordHistory();
  void setDocumentFromSolver(DsfDocument newDoc);
  List<ReferenceGeometry> get allReferenceGeometries;

  String? _selectedConstraintId;
  String? get selectedConstraintId => _selectedConstraintId;

  CadConstraintType? _activeConstraintPickType;
  CadConstraintType? get activeConstraintPickType => _activeConstraintPickType;

  EntityRef? _firstPickedEntityRef;
  EntityRef? get firstPickedEntityRef => _firstPickedEntityRef;

  List<String> _currentSolverConflicts = [];
  List<String> get currentSolverConflicts => List.unmodifiable(_currentSolverConflicts);

  bool _showConstraintsOnCanvas = true;
  bool get showConstraintsOnCanvas => _showConstraintsOnCanvas;

  bool _isConstraintManagerOpen = false;
  bool get isConstraintManagerOpen => _isConstraintManagerOpen;

  void setConstraintManagerOpen(bool open) {
    if (_isConstraintManagerOpen == open) return;
    _isConstraintManagerOpen = open;
    notifyListeners();
  }

  void toggleConstraintManager() {
    _isConstraintManagerOpen = !_isConstraintManagerOpen;
    notifyListeners();
  }

  void toggleShowConstraintsOnCanvas() {
    _showConstraintsOnCanvas = !_showConstraintsOnCanvas;
    notifyListeners();
  }

  void selectConstraintId(String? id) {
    if (_selectedConstraintId == id) return;
    _selectedConstraintId = id;
    notifyListeners();
  }

  /// Returns current list of upgraded [ConstraintDefinition]s
  List<ConstraintDefinition> get activeConstraintDefinitions => document.constraints
      .map((c) => ConstraintDefinition.fromLegacy(c))
      .toList();

  /// Adds an upgraded constraint definition and solves
  void addConstraintDefinition(ConstraintDefinition constraint) {
    recordHistory();
    final legacyList = [...document.constraints, constraint.toLegacy()];
    final updatedDoc = document.copyWith(constraints: legacyList);

    final res = GeometricConstraintSolver.solve(
      document: updatedDoc,
      customReferences: allReferenceGeometries,
    );

    _currentSolverConflicts = res.conflicts;
    setDocumentFromSolver(res.updatedDocument);
    _selectedConstraintId = constraint.id;
    notifyListeners();
  }

  /// Removes a constraint by ID and re-solves
  void removeConstraintDefinition(String id) {
    recordHistory();
    final legacyList = document.constraints.where((c) => c.id != id).toList();
    final updatedDoc = document.copyWith(constraints: legacyList);

    if (_selectedConstraintId == id) _selectedConstraintId = null;

    final res = GeometricConstraintSolver.solve(
      document: updatedDoc,
      customReferences: allReferenceGeometries,
    );

    _currentSolverConflicts = res.conflicts;
    setDocumentFromSolver(res.updatedDocument);
    notifyListeners();
  }

  /// Toggles constraint active/suppressed status
  void toggleConstraintDefinition(String id) {
    recordHistory();
    final legacyList = document.constraints.map((c) {
      if (c.id == id) {
        return c.copyWith(isActive: !c.isActive);
      }
      return c;
    }).toList();

    final updatedDoc = document.copyWith(constraints: legacyList);
    final res = GeometricConstraintSolver.solve(
      document: updatedDoc,
      customReferences: allReferenceGeometries,
    );

    _currentSolverConflicts = res.conflicts;
    setDocumentFromSolver(res.updatedDocument);
    notifyListeners();
  }

  /// Solves all active constraints on current document
  GeometricSolverResult solveAllConstraints() {
    recordHistory();
    final res = GeometricConstraintSolver.solve(
      document: document,
      customReferences: allReferenceGeometries,
    );

    _currentSolverConflicts = res.conflicts;
    if (res.success) {
      setDocumentFromSolver(res.updatedDocument);
      notifyListeners();
    }
    return res;
  }

  /// Updates a constraint definition (e.g. edited target value, linked parameterId) and re-solves
  void updateConstraintDefinition(ConstraintDefinition updated) {
    recordHistory();
    final legacyList = document.constraints.map((c) {
      if (c.id == updated.id) {
        return updated.toLegacy();
      }
      return c;
    }).toList();

    final updatedDoc = document.copyWith(constraints: legacyList);
    final res = GeometricConstraintSolver.solve(
      document: updatedDoc,
      customReferences: allReferenceGeometries,
    );

    _currentSolverConflicts = res.conflicts;
    setDocumentFromSolver(res.updatedDocument);
    notifyListeners();
  }

  // ===========================================================================
  // Interactive 2-Click Constraint Authoring Workflow
  // ===========================================================================

  void startInteractiveConstraintPick(CadConstraintType type) {
    _activeConstraintPickType = type;
    _firstPickedEntityRef = null;
    notifyListeners();
  }

  void cancelInteractiveConstraintPick() {
    _activeConstraintPickType = null;
    _firstPickedEntityRef = null;
    notifyListeners();
  }

  /// Registers an entity pick for the interactive constraint workflow.
  /// If [type.requiresTwoEntities] is false, creates constraint immediately.
  /// If true, records 1st entity on first tap, and creates constraint on 2nd tap.
  bool registerEntityPickForConstraint(
    EntityRef ref, {
    double? targetValue,
    String? parameterId,
  }) {
    if (_activeConstraintPickType == null) return false;
    final type = _activeConstraintPickType!;

    if (!type.requiresTwoEntities) {
      // Single entity constraint (Horizontal, Vertical, Fixed, Radius, Diameter)
      final constraint = ConstraintDefinition(
        id: 'CONST_${DateTime.now().millisecondsSinceEpoch}',
        type: type,
        references: [ref],
        targetValue: targetValue,
        parameterId: parameterId,
      );
      addConstraintDefinition(constraint);
      cancelInteractiveConstraintPick();
      return true;
    }

    if (_firstPickedEntityRef == null) {
      // First entity picked
      _firstPickedEntityRef = ref;
      notifyListeners();
      return false; // Waiting for 2nd entity
    } else {
      // Second entity picked -> create constraint
      double? resolvedTarget = targetValue;
      if (resolvedTarget == null && type == CadConstraintType.distance) {
        resolvedTarget = ReferenceGeometryEngine.measureDistance(
          refA: _firstPickedEntityRef!,
          refB: ref,
          document: document,
          customReferences: allReferenceGeometries,
        );
      }

      final constraint = ConstraintDefinition(
        id: 'CONST_${DateTime.now().millisecondsSinceEpoch}',
        type: type,
        references: [_firstPickedEntityRef!, ref],
        targetValue: resolvedTarget,
        parameterId: parameterId,
      );
      addConstraintDefinition(constraint);
      cancelInteractiveConstraintPick();
      return true;
    }
  }
}
