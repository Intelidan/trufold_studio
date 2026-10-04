import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cnc_punch_primitive.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';

void main() {
  test('Tray 90 deg outside riser height scaling from 50 -> 75 -> 100 -> 50 without delay', () async {
    final outFile = File('assets/dsf_templates/tray_accessories/90_deg_outside_riser_100X50.dsf');
    final outDoc = DsfDocument.fromJson(jsonDecode(await outFile.readAsString()));

    final vm = SheetMetalStudioViewModel();
    vm.loadDocument(outDoc);

    // Initial state
    expect(vm.scalingController, isNull);

    // Step 1: User increases height to 75mm (SS2 in user prompt)
    vm.applyCmsMorphParameter('height', 75.0);

    final ctrl75 = vm.scalingController;
    expect(ctrl75, isNotNull);
    final hParam75 = ctrl75!.model.parameters['height'];
    expect(hParam75, isNotNull);
    expect(hParam75!.baselineValue, equals(50.0), reason: 'Baseline height must be 50.0mm');
    expect(hParam75.currentValue, equals(75.0), reason: 'Current height must be 75.0mm');

    final preview75 = ctrl75.currentPreview;
    expect(preview75, isNotNull);
    final doc75 = preview75!.scaledDocument;

    // Check 2D blank bounds at H=75:
    // Baseline was [0, 226]. With delta = +25, left moves by -25 (minX = -25), right moves by +25 (maxX = 251).
    // Total span = 276.0mm (left cheek 75mm, base floor 100mm, right cheek 75mm, flanges 2x13mm = 276mm).
    final xs75 = doc75.outerContour.map((p) => p.x).toList();
    final minX75 = xs75.reduce((a, b) => a < b ? a : b);
    final maxX75 = xs75.reduce((a, b) => a > b ? a : b);
    expect(minX75, closeTo(-25.0, 0.01));
    expect(maxX75, closeTo(251.0, 0.01));
    expect(maxX75 - minX75, closeTo(276.0, 0.01), reason: 'Total width at H=75 must be 276.0mm');

    // Check ports at H=75
    final ports75 = preview75.derivedPorts;
    expect(ports75.length, equals(2));
    expect(ports75[0].height, closeTo(75.0, 0.01));
    expect(ports75[1].height, closeTo(75.0, 0.01));

    // Check coupler slots at H=75: slotCols = max(1, (75/25).round()) = 3
    final couplerSlots75 = doc75.punches.where((p) => p.role == CncPunchRole.coupler).toList();
    // 4 arms * 2 rows * 3 cols = 24 coupler slots
    expect(couplerSlots75.length, equals(24));

    // Step 2: User increases height further to 100mm (SS3 in user prompt)
    vm.applyCmsMorphParameter('height', 100.0);

    final ctrl100 = vm.scalingController!;
    final hParam100 = ctrl100.model.parameters['height']!;
    expect(hParam100.baselineValue, equals(50.0), reason: 'Baseline height must remain 50.0mm');
    expect(hParam100.currentValue, equals(100.0), reason: 'Current height must be 100.0mm');

    final preview100 = ctrl100.currentPreview!;
    final doc100 = preview100.scaledDocument;

    // Check 2D blank bounds at H=100:
    // With delta = +50, left moves by -50 (minX = -50), right moves by +50 (maxX = 276).
    // Total span = 326.0mm (left cheek 100mm, base floor 100mm, right cheek 100mm, flanges 2x13mm = 326mm).
    final xs100 = doc100.outerContour.map((p) => p.x).toList();
    final minX100 = xs100.reduce((a, b) => a < b ? a : b);
    final maxX100 = xs100.reduce((a, b) => a > b ? a : b);
    expect(minX100, closeTo(-50.0, 0.01));
    expect(maxX100, closeTo(276.0, 0.01));
    expect(maxX100 - minX100, closeTo(326.0, 0.01), reason: 'Total width at H=100 must be 326.0mm');

    // Check ports at H=100
    final ports100 = preview100.derivedPorts;
    expect(ports100[0].height, closeTo(100.0, 0.01));
    expect(ports100[1].height, closeTo(100.0, 0.01));

    // Check coupler slots at H=100: slotCols = max(1, (100/25).round()) = 4
    final couplerSlots100 = doc100.punches.where((p) => p.role == CncPunchRole.coupler).toList();
    // 4 arms * 2 rows * 4 cols = 32 coupler slots
    expect(couplerSlots100.length, equals(32));

    // Middle connecting holes at H=100: 2 holes per side (50mm pitch) = 4 holes total
    final middleSlots100 = doc100.punches.where((p) => p.role == CncPunchRole.general).toList();
    expect(middleSlots100.length, equals(4));

    // Step 3: User resets / scales back to 50mm
    vm.applyCmsMorphParameter('height', 50.0);

    final ctrl50 = vm.scalingController!;
    final preview50 = ctrl50.currentPreview!;
    final doc50 = preview50.scaledDocument;

    final xs50 = doc50.outerContour.map((p) => p.x).toList();
    final minX50 = xs50.reduce((a, b) => a < b ? a : b);
    final maxX50 = xs50.reduce((a, b) => a > b ? a : b);
    expect(minX50, closeTo(0.0, 0.01));
    expect(maxX50, closeTo(226.0, 0.01));
    expect(maxX50 - minX50, closeTo(226.0, 0.01), reason: 'Total width at H=50 must return to 226.0mm');
  });
}
