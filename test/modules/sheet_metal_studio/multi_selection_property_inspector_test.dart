// =============================================================================
// multi_selection_property_inspector_test.dart
//
// Tests for multi-selection property inspector persistence, keyboard shortcut
// toggling, menu items in View and Edit menus, and CadPropertyInspector widgets.
// =============================================================================

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/cad_property_inspector.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/punch_property_sheet.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/studio/studio_menu_bar.dart';

void main() {
  group('Multi-Selection Property Inspector Tests', () {
    late SheetMetalStudioViewModel vm;

    setUp(() async {
      final file = File('assets/dxf_templates/trunking_accessories/45_deg_bend_100x100.dsf');
      final doc = DsfDocument.fromJson(jsonDecode(await file.readAsString()) as Map<String, dynamic>);
      vm = SheetMetalStudioViewModel();
      vm.loadDocument(doc);
    });

    test('togglePropertyInspector flips isPropertyInspectorOpen', () {
      expect(vm.isPropertyInspectorOpen, isTrue);

      vm.togglePropertyInspector();
      expect(vm.isPropertyInspectorOpen, isFalse);

      vm.togglePropertyInspector();
      expect(vm.isPropertyInspectorOpen, isTrue);
    });

    test('selectEntities opens property inspector for multi-selection', () {
      vm.setPropertyInspectorOpen(false);
      expect(vm.isPropertyInspectorOpen, isFalse);

      final p1 = vm.document.punches[0].id;
      final p2 = vm.document.punches[1].id;

      // Select multiple punches
      vm.selectEntities([p1, p2]);
      expect(vm.selectedEntityIds.length, equals(2));
      expect(vm.isPropertyInspectorOpen, isTrue);
    });

    testWidgets('CadPropertyInspector displays PunchPropertySheet for homogeneous punch selection',
        (tester) async {
      final p1 = vm.document.punches[0].id;
      final p2 = vm.document.punches[1].id;
      vm.selectEntities([p1, p2]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CadPropertyInspector(viewModel: vm),
          ),
        ),
      );

      // Verify PunchPropertySheet is rendered
      expect(find.byType(PunchPropertySheet), findsOneWidget);
      expect(find.textContaining('2 HOLES'), findsOneWidget);
    });

    testWidgets('CadPropertyInspector displays DocumentPropertySheet when nothing is selected',
        (tester) async {
      vm.clearSelection();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CadPropertyInspector(viewModel: vm),
          ),
        ),
      );

      // Verify Document Properties header is rendered
      expect(find.text('DOCUMENT PROPERTIES'), findsOneWidget);
      expect(find.textContaining('Select All Entities'), findsOneWidget);
    });

    testWidgets('CadPropertyInspector displays MultiEntityPropertySheet for mixed selection',
        (tester) async {
      final p1 = vm.document.punches.first.id;
      final b1 = vm.document.bends.first.id;
      vm.selectEntities([p1, b1]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CadPropertyInspector(viewModel: vm),
          ),
        ),
      );

      // Verify Multi-entity inspector is rendered
      expect(find.text('2 ITEMS SELECTED'), findsOneWidget);
      expect(find.text('Punches / Holes'), findsOneWidget);
      expect(find.text('Press-Brake Bends'), findsOneWidget);
    });

    testWidgets('View menu contains CAD Properties Inspector with Ctrl+1 shortcut',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudioMenuBar(
              viewModel: vm,
              onNewTab: () {},
              onOpenFile: () {},
              onSaveFile: () {},
              onConfirmClearAll: (_, __) async {},
            ),
          ),
        ),
      );

      // Tap "View" menu button
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();

      // Verify "CAD Properties Inspector" and "Ctrl+1" exist in the menu
      expect(find.text('CAD Properties Inspector'), findsOneWidget);
      expect(find.text('Ctrl+1'), findsOneWidget);

      // Tap on CAD Properties Inspector
      expect(vm.isPropertyInspectorOpen, isTrue);
      await tester.tap(find.text('CAD Properties Inspector'));
      await tester.pumpAndSettle();

      // Must be toggled to false
      expect(vm.isPropertyInspectorOpen, isFalse);
    });

    testWidgets('Edit menu contains Properties Inspector with Ctrl+1 shortcut',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudioMenuBar(
              viewModel: vm,
              onNewTab: () {},
              onOpenFile: () {},
              onSaveFile: () {},
              onConfirmClearAll: (_, __) async {},
            ),
          ),
        ),
      );

      // Tap "Edit" menu button
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      // Verify "Properties Inspector" and "Ctrl+1" exist in the menu
      expect(find.text('Properties Inspector'), findsOneWidget);
      expect(find.text('Ctrl+1'), findsOneWidget);

      // Tap on Properties Inspector
      expect(vm.isPropertyInspectorOpen, isTrue);
      await tester.tap(find.text('Properties Inspector'));
      await tester.pumpAndSettle();

      // Must be toggled to false
      expect(vm.isPropertyInspectorOpen, isFalse);
    });
  });
}
