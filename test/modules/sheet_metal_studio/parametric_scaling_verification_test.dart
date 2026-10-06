import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';

void main() {
  test('Verify updateTemplateParameter on loaded DSF document', () async {
    final file = File('assets/dsf_templates/tray_accessories/45_deg_bend_100x50.dsf');
    final jsonStr = await file.readAsString();
    final dsf = DsfDocument.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);

    final vm = SheetMetalStudioViewModel();
    vm.loadDocument(dsf);

    final initialBlankW = vm.document.blankWidthMm;
    final initialMeshW = vm.currentMesh.boundWidth;

    // What canvas_port_dimension_editor calls:
    vm.updateTemplateParameter('width', 200.0);

    expect(vm.isTeachScalingActive, isTrue);
    expect(vm.document.blankWidthMm, greaterThan(initialBlankW + 50.0));
    expect(vm.currentMesh.boundWidth, greaterThan(initialMeshW + 50.0));

    // Commit scaling
    vm.commitCmsScaling();
    expect(vm.isTeachScalingActive, isFalse);
    expect(vm.document.blankWidthMm, greaterThan(initialBlankW + 50.0));
  });

  test('Verify port1_width scaling on loaded DSF document', () async {
    final file = File('assets/dsf_templates/tray_accessories/45_deg_bend_100x50.dsf');
    final jsonStr = await file.readAsString();
    final dsf = DsfDocument.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);

    final vm = SheetMetalStudioViewModel();
    vm.loadDocument(dsf);

    final initialBlankW = vm.document.blankWidthMm;

    // What happens if key is 'port1_width'?
    vm.applyCmsMorphParameter('port1_width', 200.0);
    expect(vm.isTeachScalingActive, isTrue);
    expect(vm.scalingController, isNotNull);
    expect(vm.document.blankWidthMm, greaterThan(initialBlankW + 50.0));

    vm.commitCmsScaling();
    expect(vm.isTeachScalingActive, isFalse);
    expect(vm.document.blankWidthMm, greaterThan(initialBlankW + 50.0));
  });

  test('Verify reducer port dimension scaling on loaded DSF document', () async {
    final file = File('assets/dsf_templates/tray_accessories/reducer_100x50x50.dsf');
    final jsonStr = await file.readAsString();
    final dsf = DsfDocument.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);

    final vm = SheetMetalStudioViewModel();
    vm.loadDocument(dsf);

    final initialBlankW = vm.document.blankWidthMm;
    final initialMeshW = vm.currentMesh.boundWidth;

    vm.updateTemplateParameter('port1_width', 200.0);
    expect(vm.isTeachScalingActive, isTrue);
    expect(vm.document.blankWidthMm, greaterThan(initialBlankW + 50.0));
    expect(vm.currentMesh.boundWidth, greaterThan(initialMeshW + 50.0));

    vm.commitCmsScaling();
    expect(vm.isTeachScalingActive, isFalse);
    expect(vm.document.blankWidthMm, greaterThan(initialBlankW + 50.0));
  });

  test('Verify 90 deg bend scaling on loaded DSF document', () async {
    final file = File('assets/dsf_templates/tray_accessories/90_deg_bend_100x50.dsf');
    final jsonStr = await file.readAsString();
    final dsf = DsfDocument.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);

    final vm = SheetMetalStudioViewModel();
    vm.loadDocument(dsf);

    final initialBlankW = vm.document.blankWidthMm;

    vm.updateTemplateParameter('width', 200.0);
    expect(vm.isTeachScalingActive, isTrue);
    expect(vm.document.blankWidthMm, greaterThan(initialBlankW + 50.0));

    vm.commitCmsScaling();
    expect(vm.isTeachScalingActive, isFalse);
    expect(vm.document.blankWidthMm, greaterThan(initialBlankW + 50.0));
  });

  test('Verify equal tee scaling on loaded DSF document', () async {
    final file = File('assets/dsf_templates/tray_accessories/equal_tee_100x50.dsf');
    final jsonStr = await file.readAsString();
    final dsf = DsfDocument.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);

    final vm = SheetMetalStudioViewModel();
    vm.loadDocument(dsf);

    final initialBlankW = vm.document.blankWidthMm;

    vm.updateTemplateParameter('width', 200.0);
    expect(vm.isTeachScalingActive, isTrue);
    expect(vm.document.blankWidthMm, greaterThan(initialBlankW + 50.0));

    vm.commitCmsScaling();
    expect(vm.isTeachScalingActive, isFalse);
    expect(vm.document.blankWidthMm, greaterThan(initialBlankW + 50.0));
  });

  test('Verify equal cross scaling on loaded DSF document', () async {
    final file = File('assets/dsf_templates/tray_accessories/equal_cross_100x50.dsf');
    final jsonStr = await file.readAsString();
    final dsf = DsfDocument.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);

    final vm = SheetMetalStudioViewModel();
    vm.loadDocument(dsf);

    final initialBlankW = vm.document.blankWidthMm;

    vm.updateTemplateParameter('width', 200.0);
    expect(vm.isTeachScalingActive, isTrue);
    expect(vm.document.blankWidthMm, greaterThan(initialBlankW + 50.0));

    vm.commitCmsScaling();
    expect(vm.isTeachScalingActive, isFalse);
    expect(vm.document.blankWidthMm, greaterThan(initialBlankW + 50.0));
  });
}
