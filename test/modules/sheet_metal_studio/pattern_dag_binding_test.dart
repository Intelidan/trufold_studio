import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/perforation_pattern.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/constraints/expression_parser_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/constraints/dependency_graph_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';
import 'package:trufold_studio/sheet_metal_studio/models/template_parameter_definition.dart';

void main() {
  group('Pattern Parameter DAG Binding Tests (Step 3 - SET 12)', () {
    test('1. Math functions (floor, ceil, round, abs, sqrt, min, max) evaluate correctly', () {
      final params = {'WIDTH': 200.0, 'MARGIN': 20.0, 'PITCH': 25.0};

      // floor((WIDTH - 2 * MARGIN) / PITCH) = floor((200 - 40) / 25) = floor(6.4) = 6.0
      expect(
        ExpressionParserEngine.evaluate('floor((WIDTH - 2 * MARGIN) / PITCH)', params),
        closeTo(6.0, 1e-4),
      );

      // ceil
      expect(
        ExpressionParserEngine.evaluate('ceil(160 / 25)', params),
        closeTo(7.0, 1e-4),
      );

      // round
      expect(
        ExpressionParserEngine.evaluate('round(6.6)', params),
        closeTo(7.0, 1e-4),
      );

      // abs
      expect(
        ExpressionParserEngine.evaluate('abs(-45.5)', params),
        closeTo(45.5, 1e-4),
      );

      // sqrt
      expect(
        ExpressionParserEngine.evaluate('sqrt(100)', params),
        closeTo(10.0, 1e-4),
      );

      // min & max
      expect(
        ExpressionParserEngine.evaluate('min(WIDTH, 50)', params),
        closeTo(50.0, 1e-4),
      );
      expect(
        ExpressionParserEngine.evaluate('max(WIDTH, 50)', params),
        closeTo(200.0, 1e-4),
      );

      // extractVariables filters out function names
      final vars = ExpressionParserEngine.extractVariables('floor((WIDTH - min(2 * MARGIN, 50)) / PITCH)');
      expect(vars, containsAll(['WIDTH', 'MARGIN', 'PITCH']));
      expect(vars, isNot(contains('floor')));
      expect(vars, isNot(contains('min')));
    });

    test('2. Dynamic formula evaluation: floor((WIDTH - 40) / 25) updates countX from 2 to 6 columns', () {
      final initialPattern = PerforationPattern(
        id: 'PAT_1',
        anchor: const CadPoint2D(100.0, 100.0),
        countX: 2,
        countY: 10,
        pitchX: 25.0,
        pitchY: 50.0,
        countXExpression: 'floor((WIDTH - 40) / 25)',
      );

      // At WIDTH = 100 mm: floor((100 - 40) / 25) = floor(2.4) = 2 columns
      final eval1 = DependencyGraphEngine.evaluatePattern(initialPattern, {'WIDTH': 100.0});
      expect(eval1.countX, 2);

      // Morph WIDTH to 200 mm: floor((200 - 40) / 25) = floor(6.4) = 6 columns
      final eval2 = DependencyGraphEngine.evaluatePattern(initialPattern, {'WIDTH': 200.0});
      expect(eval2.countX, 6);

      // Morph WIDTH to 300 mm: floor((300 - 40) / 25) = floor(10.4) = 10 columns
      final eval3 = DependencyGraphEngine.evaluatePattern(initialPattern, {'WIDTH': 300.0});
      expect(eval3.countX, 10);
    });

    test('3. Linked pitch parameter updates grid pitch', () {
      final pattern = PerforationPattern(
        id: 'PAT_PITCH',
        anchor: const CadPoint2D(0.0, 0.0),
        countX: 4,
        countY: 20,
        pitchX: 25.0,
        pitchY: 50.0,
        pitchYParameter: 'PITCH_Y',
      );

      final eval = DependencyGraphEngine.evaluatePattern(pattern, {'PITCH_Y': 75.0});
      expect(eval.pitchY, closeTo(75.0, 1e-4));
      expect(eval.pitchX, closeTo(25.0, 1e-4));
    });

    test('4. Circular dependency detection throws CircularDependencyException', () {
      final dag = DependencyGraphEngine();

      // WIDTH -> pattern:PAT_1 (pattern depends on WIDTH)
      dag.addNode(id: 'WIDTH', type: DependencyNodeType.parameter);
      dag.addNode(id: 'pattern:PAT_1', type: DependencyNodeType.pattern);
      dag.addDependency(sourceId: 'WIDTH', dependentId: 'pattern:PAT_1');

      // Attempting to make WIDTH depend on pattern:PAT_1 creates a cycle!
      expect(
        () => dag.addDependency(sourceId: 'pattern:PAT_1', dependentId: 'WIDTH'),
        throwsA(isA<CircularDependencyException>()),
      );
    });

    test('5. ViewModel recalculatePatternsFromParameters updates patterns on template morphing', () {
      final vm = SheetMetalStudioViewModel();
      vm.loadTemplate(TemplateParameterDefinition.cableTrayStraight(
        width: 100.0,
        height: 50.0,
        length: 1000.0,
      ));


      vm.applyPerforationPattern(
        center: const CadPoint2D(100.0, 500.0),
        countX: 2,
        countY: 10,
        pitchX: 25.0,
        pitchY: 50.0,
        slotWidth: 10.0,
        slotHeight: 25.0,
        staggered: false,
      );

      // Replace pattern with one containing the expression
      final existingPat = vm.document.perforationPatterns.first;
      vm.replacePattern(existingPat.copyWith(countXExpression: 'floor((width - 40) / 25)'));

      // Morph width to 200.0 mm
      vm.updateTemplateParameter('width', 200.0);

      final updatedPattern = vm.document.perforationPatterns.first;
      expect(updatedPattern.countX, 6);
    });
  });
}
