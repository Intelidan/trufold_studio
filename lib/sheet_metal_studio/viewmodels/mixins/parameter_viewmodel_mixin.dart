// =============================================================================
// parameter_viewmodel_mixin.dart
//
// Mixin for Named Parameters & Mathematical Expressions per Phase 1 Master Guide
// Sections 22, 23, 24, 35 & Sets 08, 09.
//
// Decouples parameter management and formula evaluations from the main ViewModel.
// =============================================================================

import 'package:flutter/foundation.dart';
import '../../models/dsf_document.dart';
import '../../engine/constraints/expression_parser_engine.dart';
import '../../engine/constraints/dependency_graph_engine.dart';

mixin ParameterViewModelMixin on ChangeNotifier {
  DsfDocument get document;
  void recordHistory();
  void onGeometryRecalculated();

  final DependencyGraphEngine _dependencyGraph = DependencyGraphEngine();
  DependencyGraphEngine get dependencyGraph => _dependencyGraph;

  final Map<String, String> _parameterFormulas = {};
  Map<String, String> get parameterFormulas => Map.unmodifiable(_parameterFormulas);

  /// Returns current parameter dictionary
  Map<String, double> get activeParameters => document.parameters;

  /// Retrieves a named parameter value
  double? getNamedParameter(String name) {
    for (final entry in document.parameters.entries) {
      if (entry.key.toLowerCase() == name.toLowerCase()) {
        return entry.value;
      }
    }
    return null;
  }

  /// Sets a named parameter value and marks its dependents dirty
  void setNamedParameter(String name, double value) {
    recordHistory();
    final newParams = Map<String, double>.from(document.parameters);
    newParams[name] = value;

    _dependencyGraph.addNode(
      id: name,
      type: DependencyNodeType.parameter,
    );
    _dependencyGraph.markDirty(name);

    // Evaluate any formulas depending on this parameter
    for (final entry in _parameterFormulas.entries) {
      final formula = entry.value;
      final vars = ExpressionParserEngine.extractVariables(formula);
      if (vars.any((v) => v.toLowerCase() == name.toLowerCase())) {
        try {
          final evaluated = ExpressionParserEngine.evaluate(formula, newParams);
          newParams[entry.key] = evaluated;
          _dependencyGraph.markDirty(entry.key);
        } catch (_) {}
      }
    }

    // Apply to document
    setDocumentParameters(newParams);
    onGeometryRecalculated();
    notifyListeners();
  }

  /// Registers a formula for a derived parameter
  void setParameterFormula(String name, String formula) {
    recordHistory();
    _parameterFormulas[name] = formula;

    // Register DAG edges
    final vars = ExpressionParserEngine.extractVariables(formula);
    _dependencyGraph.addNode(id: name, type: DependencyNodeType.parameter);
    for (final v in vars) {
      _dependencyGraph.addNode(id: v, type: DependencyNodeType.parameter);
      if (!_dependencyGraph.wouldCreateCycle(v, name)) {
        _dependencyGraph.addDependency(sourceId: v, dependentId: name);
      }
    }

    // Evaluate immediately
    final newParams = Map<String, double>.from(document.parameters);
    try {
      final evaluated = ExpressionParserEngine.evaluate(formula, newParams);
      newParams[name] = evaluated;
      setDocumentParameters(newParams);
      onGeometryRecalculated();
    } catch (_) {}
    notifyListeners();
  }

  /// Abstract hook implemented by ViewModel to update document.parameters
  void setDocumentParameters(Map<String, double> newParams);
}
