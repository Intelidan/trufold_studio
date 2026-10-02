// =============================================================================
// dynamic_dimension_input_test.dart
//
// Comprehensive test suite for Dynamic Dimension Input:
// 1. DynamicDimensionInputState buffer parsing, key append, backspace, and Tab.
// 2. computeEffectiveEndpoint for lines, rectangles, circles, punches, and dimensions.
// 3. SheetMetalStudioViewModel integration:
//    - Real-time rubber band recalculation while typing digits
//    - Commit on Enter
//    - Escape handling
//    - End-to-end creation of cut line, rectangle, circle, and dimension
// =============================================================================

import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dynamic_dimension_input_state.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. DynamicDimensionInputState Logic & Formatting', () {
    late DynamicDimensionInputState state;
    late ActiveToolConfig config;

    setUp(() {
      state = DynamicDimensionInputState();
      config = ActiveToolConfig();
    });

    test('Appends digits and validates decimal points', () {
      expect(state.hasValue, isFalse);
      expect(state.primaryValue, isNull);

      state.appendChar('1');
      state.appendChar('2');
      state.appendChar('.');
      state.appendChar('5');
      state.appendChar('.'); // Duplicate decimal ignored

      expect(state.hasValue, isTrue);
      expect(state.hasPrimary, isTrue);
      expect(state.primaryBuffer, equals('12.5'));
      expect(state.primaryValue, equals(12.5));
    });

    test('Toggles to secondary buffer on comma or x', () {
      state.appendChar('8');
      state.appendChar('0');
      expect(state.isEditingSecondary, isFalse);

      state.appendChar(',');
      expect(state.isEditingSecondary, isTrue);

      state.appendChar('4');
      state.appendChar('5');

      expect(state.primaryValue, equals(80.0));
      expect(state.secondaryValue, equals(45.0));
      expect(state.hasSecondary, isTrue);
    });

    test('Handles backspace across secondary and primary buffers', () {
      state.appendChar('1');
      state.appendChar('0');
      state.appendChar('x');
      state.appendChar('5');

      expect(state.secondaryBuffer, equals('5'));
      state.backspace();
      expect(state.secondaryBuffer, isEmpty);

      // Next backspace exits secondary editing mode
      state.backspace();
      expect(state.isEditingSecondary, isFalse);
      expect(state.primaryBuffer, equals('10'));

      state.backspace();
      expect(state.primaryBuffer, equals('1'));
    });

    test('Line mode: computeEffectiveEndpoint projects typed length along cursor vector', () {
      state.setAnchorPoint(const CadPoint2D(0, 0));
      state.setCursorPoint(const CadPoint2D(10, 0)); // Horizontal along +X

      state.appendChar('1');
      state.appendChar('5');
      state.appendChar('0'); // 150mm

      final epHorizontal = state.computeEffectiveEndpoint(
        toolMode: StudioToolMode.addCut,
        toolConfig: config,
      );
      expect(epHorizontal.x, closeTo(150.0, 1e-4));
      expect(epHorizontal.y, closeTo(0.0, 1e-4));

      // Diagonal 45 degrees
      state.setCursorPoint(const CadPoint2D(50, 50));
      final epDiagonal = state.computeEffectiveEndpoint(
        toolMode: StudioToolMode.addBend,
        toolConfig: config,
      );
      final expectedDist = 150.0 / math.sqrt(2);
      expect(epDiagonal.x, closeTo(expectedDist, 1e-4));
      expect(epDiagonal.y, closeTo(expectedDist, 1e-4));
    });

    test('Rectangle mode: computeEffectiveEndpoint computes typed width & height', () {
      state.setAnchorPoint(const CadPoint2D(10, 20));
      state.setCursorPoint(const CadPoint2D(30, 40)); // Quadrant (+X, +Y)

      state.appendChar('1');
      state.appendChar('0');
      state.appendChar('0'); // Width: 100
      state.appendChar(',');
      state.appendChar('6');
      state.appendChar('0'); // Height: 60

      final ep = state.computeEffectiveEndpoint(
        toolMode: StudioToolMode.drawRectangle,
        toolConfig: config,
      );
      expect(ep.x, closeTo(110.0, 1e-4)); // 10 + 100
      expect(ep.y, closeTo(80.0, 1e-4));  // 20 + 60
    });

    test('Circle mode: computeEffectiveEndpoint projects typed radius', () {
      state.setAnchorPoint(const CadPoint2D(50, 50));
      state.setCursorPoint(const CadPoint2D(100, 50)); // East

      state.appendChar('3');
      state.appendChar('5'); // Radius: 35

      final ep = state.computeEffectiveEndpoint(
        toolMode: StudioToolMode.drawCircle,
        toolConfig: config,
      );
      expect(ep.x, closeTo(85.0, 1e-4)); // 50 + 35
      expect(ep.y, closeTo(50.0, 1e-4));
    });
  });

  group('2. SheetMetalStudioViewModel Dynamic Input Key Events & Drawing', () {
    late SheetMetalStudioViewModel vm;

    setUp(() {
      vm = SheetMetalStudioViewModel();
    });

    test('Digit key events update dynamicInputState and rubberBandEndpoint in real time', () {
      vm.setToolMode(StudioToolMode.addCut);
      // Set pending start at (10, 10)
      vm.setPendingBendStart(const CadPoint2D(10, 10));
      vm.updateCursorMm(const CadPoint2D(60, 10)); // Vector length = 50

      expect(vm.isDrawingInProgress, isTrue);

      // Send key '1', '2', '0'
      vm.handleDynamicInputKey(const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.digit1,
        logicalKey: LogicalKeyboardKey.digit1,
        character: '1',
        timeStamp: Duration.zero,
      ));
      vm.handleDynamicInputKey(const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.digit2,
        logicalKey: LogicalKeyboardKey.digit2,
        character: '2',
        timeStamp: Duration.zero,
      ));
      vm.handleDynamicInputKey(const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.digit0,
        logicalKey: LogicalKeyboardKey.digit0,
        character: '0',
        timeStamp: Duration.zero,
      ));

      expect(vm.dynamicInputState.primaryBuffer, equals('120'));
      expect(vm.dynamicInputState.primaryValue, equals(120.0));

      // Rubber band endpoint must be stretched to exactly 120mm from anchor along (1, 0)
      expect(vm.rubberBandEndpoint, isNotNull);
      expect(vm.rubberBandEndpoint!.x, closeTo(130.0, 1e-4)); // 10 + 120
      expect(vm.rubberBandEndpoint!.y, closeTo(10.0, 1e-4));
    });

    test('Enter key commits cut line with exact typed dimension', () {
      vm.setToolMode(StudioToolMode.addCut);
      vm.setPendingBendStart(const CadPoint2D(0, 0));
      vm.updateCursorMm(const CadPoint2D(20, 0)); // Horizontal

      // Type 150
      for (final char in ['1', '5', '0']) {
        vm.handleDynamicInputKey(KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.digit1,
          logicalKey: LogicalKeyboardKey(char.codeUnitAt(0)),
          character: char,
          timeStamp: Duration.zero,
        ));
      }

      final initialCutCount = vm.document.cutLines.length;

      // Commit via Enter key
      final consumed = vm.handleDynamicInputKey(const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.enter,
        logicalKey: LogicalKeyboardKey.enter,
        timeStamp: Duration.zero,
      ));

      expect(consumed, isTrue);
      expect(vm.document.cutLines.length, equals(initialCutCount + 1));
      final lastCut = vm.document.cutLines.last;
      expect(lastCut.p1.x, closeTo(0.0, 1e-4));
      expect(lastCut.p1.y, closeTo(0.0, 1e-4));
      expect(lastCut.p2.x, closeTo(150.0, 1e-4));
      expect(lastCut.p2.y, closeTo(0.0, 1e-4));
      expect(lastCut.length, closeTo(150.0, 1e-4));
      expect(vm.isDrawingInProgress, isFalse);
    });

    test('Escape key cancels active drawing and resets dynamic input state', () {
      vm.setToolMode(StudioToolMode.addBend);
      vm.setPendingBendStart(const CadPoint2D(20, 20));
      vm.updateCursorMm(const CadPoint2D(40, 40));

      vm.handleDynamicInputKey(const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.digit5,
        logicalKey: LogicalKeyboardKey.digit5,
        character: '5',
        timeStamp: Duration.zero,
      ));

      expect(vm.isDrawingInProgress, isTrue);
      expect(vm.dynamicInputState.hasValue, isTrue);

      // 1st Escape key clears buffer
      final consumed1 = vm.handleDynamicInputKey(const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.escape,
        logicalKey: LogicalKeyboardKey.escape,
        timeStamp: Duration.zero,
      ));

      expect(consumed1, isTrue);
      expect(vm.isDrawingInProgress, isTrue);
      expect(vm.dynamicInputState.hasValue, isFalse);

      // 2nd Escape key cancels active drawing
      final consumed2 = vm.handleDynamicInputKey(const KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.escape,
        logicalKey: LogicalKeyboardKey.escape,
        timeStamp: Duration.zero,
      ));

      expect(consumed2, isTrue);
      expect(vm.isDrawingInProgress, isFalse);
      expect(vm.rubberBandEndpoint, isNull);
    });

    test('Circle punch creation with typed radius creates punch of exact diameter', () {
      vm.setToolMode(StudioToolMode.drawCircle);
      vm.setPendingBendStart(const CadPoint2D(50, 50));
      vm.updateCursorMm(const CadPoint2D(70, 50));

      // Type 30 (radius 30 => diameter 60)
      for (final char in ['3', '0']) {
        vm.handleDynamicInputKey(KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.digit3,
          logicalKey: LogicalKeyboardKey(char.codeUnitAt(0)),
          character: char,
          timeStamp: Duration.zero,
        ));
      }

      final initialPunches = vm.document.punches.length;
      vm.commitCurrentDrawingWithDynamicInput();

      expect(vm.document.punches.length, equals(initialPunches + 1));
      final circlePunch = vm.document.punches.last;
      expect(circlePunch.center.x, closeTo(50.0, 1e-4));
      expect(circlePunch.center.y, closeTo(50.0, 1e-4));
      expect(circlePunch.diameterMm, closeTo(60.0, 1e-4));
    });

    test('Rectangle drawing with typed width and height creates closed cutout void punch', () {
      vm.setToolMode(StudioToolMode.drawRectangle);
      vm.setPendingBendStart(const CadPoint2D(0, 0));
      vm.updateCursorMm(const CadPoint2D(10, 10));

      // Type 120 x 80
      for (final char in ['1', '2', '0', ',', '8', '0']) {
        vm.handleDynamicInputKey(KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.digit1,
          logicalKey: LogicalKeyboardKey(char.codeUnitAt(0)),
          character: char,
          timeStamp: Duration.zero,
        ));
      }

      final initialPunches = vm.document.punches.length;
      vm.commitCurrentDrawingWithDynamicInput();

      expect(vm.document.punches.length, equals(initialPunches + 1));
      final voidPunch = vm.document.punches.last;
      expect(voidPunch.widthMm, closeTo(120.0, 1e-4));
      expect(voidPunch.lengthMm, closeTo(80.0, 1e-4));
    });

    test('Punch square creation with typed width and height creates exact punch', () {
      vm.setToolMode(StudioToolMode.addPunchSquare);
      vm.setPendingBendStart(const CadPoint2D(0, 0));
      vm.updateCursorMm(const CadPoint2D(10, 10));

      // Type 80 x 40
      for (final char in ['8', '0', ',', '4', '0']) {
        vm.handleDynamicInputKey(KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.digit8,
          logicalKey: LogicalKeyboardKey(char.codeUnitAt(0)),
          character: char,
          timeStamp: Duration.zero,
        ));
      }

      final initialPunches = vm.document.punches.length;
      vm.commitCurrentDrawingWithDynamicInput();

      expect(vm.document.punches.length, equals(initialPunches + 1));
      final rectPunch = vm.document.punches.last;
      expect(rectPunch.widthMm, closeTo(80.0, 1e-4));
      expect(rectPunch.lengthMm, closeTo(40.0, 1e-4));
    });

    test('Dimension tool with typed value creates and drives dimension', () {
      vm.setToolMode(StudioToolMode.addDimension);
      vm.setPendingBendStart(const CadPoint2D(0, 0));
      vm.updateCursorMm(const CadPoint2D(50, 0));

      // Type 75
      for (final char in ['7', '5']) {
        vm.handleDynamicInputKey(KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.digit7,
          logicalKey: LogicalKeyboardKey(char.codeUnitAt(0)),
          character: char,
          timeStamp: Duration.zero,
        ));
      }

      final initialDims = vm.document.dimensions.length;
      vm.commitCurrentDrawingWithDynamicInput();

      expect(vm.document.dimensions.length, equals(initialDims + 1));
      final dim = vm.document.dimensions.last;
      expect(dim.pointA!.x, closeTo(0.0, 1e-4));
      expect(dim.pointB!.x, closeTo(75.0, 1e-4));
    });
  });
}
