import 'dart:math' as math;
import '../../models/perforation_pattern.dart';
import 'expression_parser_engine.dart';
// =============================================================================
// dependency_graph_engine.dart
//
// Directed Acyclic Graph (DAG) & Incremental Recalculation Engine
// per Phase 1 Master Guide Sections 25, 26, 27, 50, 68 & Set 10.
//
// Features:
// - Explicit dependencies: Parameter -> Constraint -> Geometry -> Feature -> 3D
// - Cycle detection: Detects circular dependencies (e.g. A -> B -> A) and reports cycle path
// - Topological ordering: Determines exact recalculation sequence
// - Dirty propagation: Only dirty nodes are recalculated; unchanged nodes are cached
// =============================================================================

enum DependencyNodeType {
  parameter,
  constraint,
  referenceGeometry,
  contourGeometry,
  cutLine,
  bendLine,
  punch,
  pattern,
  mesh3d,
}

class DependencyNode {
  final String id;
  final DependencyNodeType type;
  final String name;
  bool isDirty;

  DependencyNode({
    required this.id,
    required this.type,
    required this.name,
    this.isDirty = false,
  });

  @override
  String toString() => '$type($name)';
}

class CircularDependencyException implements Exception {
  final List<String> cyclePath;
  const CircularDependencyException(this.cyclePath);

  @override
  String toString() =>
      'CircularDependencyException: Circular dependency detected: ${cyclePath.join(' -> ')}';
}

class DependencyGraphEngine {
  final Map<String, DependencyNode> _nodes = {};
  final Map<String, Set<String>> _dependents = {}; // node -> nodes that depend on it
  final Map<String, Set<String>> _precedents = {}; // node -> nodes it depends on

  Map<String, DependencyNode> get nodes => Map.unmodifiable(_nodes);
  int get nodeCount => _nodes.length;
  Set<String> getDirectDependents(String id) =>
      Set.unmodifiable(_dependents[id] ?? const {});

  void clear() {
    _nodes.clear();
    _dependents.clear();
    _precedents.clear();
  }

  /// Adds a node to the graph if not already registered
  void addNode({
    required String id,
    required DependencyNodeType type,
    String? name,
  }) {
    if (!_nodes.containsKey(id)) {
      _nodes[id] = DependencyNode(
        id: id,
        type: type,
        name: name ?? id,
      );
      _dependents[id] = {};
      _precedents[id] = {};
    }
  }

  /// Adds a directed dependency: [dependentId] depends on [sourceId]
  /// (i.e. When sourceId changes, dependentId must recalculate)
  void addDependency({
    required String sourceId,
    required String dependentId,
  }) {
    if (!_nodes.containsKey(sourceId)) {
      addNode(id: sourceId, type: DependencyNodeType.parameter);
    }
    if (!_nodes.containsKey(dependentId)) {
      addNode(id: dependentId, type: DependencyNodeType.constraint);
    }

    _dependents.putIfAbsent(sourceId, () => {}).add(dependentId);
    _precedents.putIfAbsent(dependentId, () => {}).add(sourceId);

    // Verify no cycle was introduced
    final cycle = findCycle();
    if (cycle != null) {
      // Revert edge to keep graph valid
      _dependents[sourceId]?.remove(dependentId);
      _precedents[dependentId]?.remove(sourceId);
      throw CircularDependencyException(cycle);
    }
  }

  /// Checks if adding an edge would create a cycle
  bool wouldCreateCycle(String sourceId, String dependentId) {
    if (sourceId == dependentId) return true;
    final visited = <String>{};
    bool dfs(String current) {
      if (current == sourceId) return true;
      visited.add(current);
      for (final next in _dependents[current] ?? const {}) {
        if (!visited.contains(next) && dfs(next)) return true;
      }
      return false;
    }
    return dfs(dependentId);
  }

  /// Detects any cycle in the graph. Returns list of node IDs in cycle, or null if acyclic.
  List<String>? findCycle() {
    final visited = <String, int>{}; // 0 = unvisited, 1 = visiting, 2 = visited
    final path = <String>[];

    for (final nodeId in _nodes.keys) {
      visited[nodeId] = 0;
    }

    List<String>? dfs(String current) {
      visited[current] = 1; // Visiting
      path.add(current);

      for (final next in _dependents[current] ?? const {}) {
        final state = visited[next] ?? 0;
        if (state == 1) {
          // Cycle found!
          final cycleStart = path.indexOf(next);
          final cycle = path.sublist(cycleStart);
          cycle.add(next);
          return cycle;
        } else if (state == 0) {
          final res = dfs(next);
          if (res != null) return res;
        }
      }

      path.removeLast();
      visited[current] = 2; // Visited
      return null;
    }

    for (final nodeId in _nodes.keys) {
      if ((visited[nodeId] ?? 0) == 0) {
        final res = dfs(nodeId);
        if (res != null) return res;
      }
    }

    return null;
  }

  /// Marks a node and all of its transitive dependents as dirty
  Set<String> markDirty(String rootId) {
    final dirtyIds = <String>{};
    void dfs(String id) {
      if (dirtyIds.contains(id)) return;
      dirtyIds.add(id);
      _nodes[id]?.isDirty = true;
      for (final dep in _dependents[id] ?? const {}) {
        dfs(dep);
      }
    }
    dfs(rootId);
    return dirtyIds;
  }

  /// Returns topologically sorted list of dirty nodes to recompute in correct order
  List<DependencyNode> getExecutionOrderForDirtyNodes() {
    final dirtyIds = _nodes.values.where((n) => n.isDirty).map((n) => n.id).toSet();
    if (dirtyIds.isEmpty) return const [];

    final inDegree = <String, int>{};
    for (final id in dirtyIds) {
      // Only count precedents that are also in the dirty set
      final prec = _precedents[id] ?? const {};
      inDegree[id] = prec.where(dirtyIds.contains).length;
    }

    final queue = <String>[];
    for (final id in dirtyIds) {
      if (inDegree[id] == 0) queue.add(id);
    }

    final order = <DependencyNode>[];
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final node = _nodes[current];
      if (node != null) order.add(node);

      for (final dep in _dependents[current] ?? const {}) {
        if (dirtyIds.contains(dep)) {
          inDegree[dep] = (inDegree[dep] ?? 1) - 1;
          if (inDegree[dep] == 0) {
            queue.add(dep);
          }
        }
      }
    }

    return order;
  }

  /// Resets all dirty flags after successful execution

  /// Registers a perforation pattern node and attaches directed dependency edges
  /// from all referenced parameter variables (e.g. WIDTH, MARGIN, PITCH_X) to the pattern.
  void registerPattern({
    required PerforationPattern pattern,
    Set<String>? activeParameterNames,
  }) {
    final patternNodeId = 'pattern:${pattern.id}';
    addNode(
      id: patternNodeId,
      type: DependencyNodeType.pattern,
      name: 'Pattern (${pattern.id})',
    );

    final formulas = <String>[
      if (pattern.countXExpression != null && pattern.countXExpression!.isNotEmpty)
        pattern.countXExpression!,
      if (pattern.countYExpression != null && pattern.countYExpression!.isNotEmpty)
        pattern.countYExpression!,
      if (pattern.pitchXParameter != null && pattern.pitchXParameter!.isNotEmpty)
        pattern.pitchXParameter!,
      if (pattern.pitchYParameter != null && pattern.pitchYParameter!.isNotEmpty)
        pattern.pitchYParameter!,
      if (pattern.marginParameter != null && pattern.marginParameter!.isNotEmpty)
        pattern.marginParameter!,
    ];

    for (final formula in formulas) {
      final variables = ExpressionParserEngine.extractVariables(formula);
      for (final v in variables) {
        addNode(id: v, type: DependencyNodeType.parameter, name: v);
        addDependency(sourceId: v, dependentId: patternNodeId);
      }
    }
  }

  /// Evaluates dynamic formula expressions on [pattern] using the [parameters] map
  /// and returns an updated PerforationPattern.
  static PerforationPattern evaluatePattern(
    PerforationPattern pattern,
    Map<String, double> parameters,
  ) {
    int countX = pattern.countX;
    int countY = pattern.countY;
    double pitchX = pattern.pitchX;
    double pitchY = pattern.pitchY;

    if (pattern.countXExpression != null && pattern.countXExpression!.trim().isNotEmpty) {
      try {
        final val = ExpressionParserEngine.evaluate(pattern.countXExpression!, parameters);
        if (!val.isNaN && !val.isInfinite && val > 0) {
          countX = math.max(1, val.toInt());
        }
      } catch (_) {}
    }

    if (pattern.countYExpression != null && pattern.countYExpression!.trim().isNotEmpty) {
      try {
        final val = ExpressionParserEngine.evaluate(pattern.countYExpression!, parameters);
        if (!val.isNaN && !val.isInfinite && val > 0) {
          countY = math.max(1, val.toInt());
        }
      } catch (_) {}
    }

    if (pattern.pitchXParameter != null && pattern.pitchXParameter!.trim().isNotEmpty) {
      try {
        final val = ExpressionParserEngine.evaluate(pattern.pitchXParameter!, parameters);
        if (!val.isNaN && !val.isInfinite && val > 0) {
          pitchX = val;
        }
      } catch (_) {}
    }

    if (pattern.pitchYParameter != null && pattern.pitchYParameter!.trim().isNotEmpty) {
      try {
        final val = ExpressionParserEngine.evaluate(pattern.pitchYParameter!, parameters);
        if (!val.isNaN && !val.isInfinite && val > 0) {
          pitchY = val;
        }
      } catch (_) {}
    }

    return pattern.copyWith(
      countX: countX,
      countY: countY,
      pitchX: pitchX,
      pitchY: pitchY,
    );
  }

  void clearDirtyFlags() {
    for (final node in _nodes.values) {
      node.isDirty = false;
    }
  }
}
