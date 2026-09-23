import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/associative_dimension_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_dimension.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/canvas_display_settings.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';

void main() {
  group('CanvasDisplaySettings & Label Styles', () {
    test('UOM formatting in mm, decimal inch, and fractional inch', () {
      const mmSettings = CanvasDisplaySettings(
        uom: CanvasUom.mm,
        decimalPlaces: 2,
      );
      expect(formatMeasure(25.4, mmSettings), '25.40 mm');
      expect(formatDimPair(25.4, 50.8, mmSettings), '25.40 × 50.80 mm');

      const inchSettings = CanvasDisplaySettings(
        uom: CanvasUom.inch,
        decimalPlaces: 2,
      );
      expect(formatMeasure(25.4, inchSettings), '1.00"');
      expect(formatDimPair(25.4, 50.8, inchSettings), '1.00 × 2.00"');

      const fracSettings = CanvasDisplaySettings(
        uom: CanvasUom.fractionalInch,
      );
      expect(formatMeasure(25.4, fracSettings), '1"');
      expect(formatMeasure(38.1, fracSettings), '1-1/2"');
      expect(formatDimPair(25.4, 38.1, fracSettings), '1" × 1-1/2"');
    });

    test('AssociativeDimensionEngine formats dimension text using canvasSettings', () {
      const dim = CadDimension(
        id: 'dim_test',
        type: CadDimensionType.horizontal,
        pointA: CadPoint2D(0, 0),
        pointB: CadPoint2D(25.4, 0),
        measuredValue: 25.4,
      );

      const mmSettings = CanvasDisplaySettings(
        uom: CanvasUom.mm,
        decimalPlaces: 1,
      );
      expect(
        AssociativeDimensionEngine.formatDimensionText(dim, mmSettings),
        '25.4 mm',
      );

      const inchSettings = CanvasDisplaySettings(
        uom: CanvasUom.inch,
        decimalPlaces: 2,
      );
      expect(
        AssociativeDimensionEngine.formatDimensionText(dim, inchSettings),
        '1.00"',
      );
    });

    test('LabelStyle copyWith updates properties correctly', () {
      const initial = LabelStyle(
        visible: true,
        fontSize: 10.0,
        color: Color(0xFF334155),
        fontWeight: FontWeight.w600,
      );

      final updated = initial.copyWith(
        fontSize: 12.0,
        color: const Color(0xFFDC2626),
        fontWeight: FontWeight.bold,
        visible: false,
      );

      expect(updated.fontSize, 12.0);
      expect(updated.color, const Color(0xFFDC2626));
      expect(updated.fontWeight, FontWeight.bold);
      expect(updated.visible, false);
      expect(updated.textStyle.fontSize, 12.0);
      expect(updated.textStyle.fontWeight, FontWeight.bold);
    });

    test('ViewModel updateCanvasDisplaySettings updates settings and notifies listeners', () {
      final vm = SheetMetalStudioViewModel();
      bool notified = false;
      vm.addListener(() => notified = true);

      final newSettings = vm.canvasDisplaySettings.copyWith(
        outsideDimLabel: const LabelStyle(
          fontSize: 13.0,
          color: Color(0xFF0369A1),
          fontWeight: FontWeight.bold,
        ),
        arcLabel: const LabelStyle(
          fontSize: 11.0,
          color: Color(0xFFDC2626),
          fontWeight: FontWeight.bold,
        ),
        dimTextLabel: const LabelStyle(
          fontSize: 12.0,
          color: Color(0xFF16A34A),
          fontWeight: FontWeight.w500,
        ),
      );

      vm.updateCanvasDisplaySettings(newSettings);

      expect(notified, isTrue);
      expect(vm.canvasDisplaySettings.outsideDimLabel.fontSize, 13.0);
      expect(vm.canvasDisplaySettings.outsideDimLabel.color, const Color(0xFF0369A1));
      expect(vm.canvasDisplaySettings.arcLabel.fontSize, 11.0);
      expect(vm.canvasDisplaySettings.arcLabel.color, const Color(0xFFDC2626));
      expect(vm.canvasDisplaySettings.dimTextLabel.fontSize, 12.0);
      expect(vm.canvasDisplaySettings.dimTextLabel.color, const Color(0xFF16A34A));
    });

    test('Default CanvasDisplaySettings starts with smallest font size (7.0) and arc labels off', () {
      const defaultSettings = CanvasDisplaySettings();
      expect(defaultSettings.bendLabel.fontSize, 7.0);
      expect(defaultSettings.faceLabel.fontSize, 7.0);
      expect(defaultSettings.arcLabel.fontSize, 7.0);
      expect(defaultSettings.dimTextLabel.fontSize, 7.0);
      expect(defaultSettings.outsideDimLabel.fontSize, 7.0);
      expect(defaultSettings.portBadgeLabel.fontSize, 7.0);
      expect(defaultSettings.arcLabel.visible, isFalse);

      final vm = SheetMetalStudioViewModel();
      expect(vm.canvasDisplaySettings.bendLabel.fontSize, 7.0);
      expect(vm.canvasDisplaySettings.faceLabel.fontSize, 7.0);
      expect(vm.canvasDisplaySettings.arcLabel.fontSize, 7.0);
      expect(vm.canvasDisplaySettings.dimTextLabel.fontSize, 7.0);
      expect(vm.canvasDisplaySettings.outsideDimLabel.fontSize, 7.0);
      expect(vm.canvasDisplaySettings.portBadgeLabel.fontSize, 7.0);
      expect(vm.canvasDisplaySettings.arcLabel.visible, isFalse);
    });
  });
}
