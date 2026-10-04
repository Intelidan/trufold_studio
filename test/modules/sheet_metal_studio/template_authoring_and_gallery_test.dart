// =============================================================================
// template_authoring_and_gallery_test.dart
//
// Widget and unit test suite for Step 4 (SET 13 & 23):
// - TemplateAuthoringWizardDialog (4-step guided template authoring)
// - DdsTemplateLibraryDialog (Unified Stored DSF & Auto-Generated CMS Library)
// - StudioRibbonToolbar integration
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/template_parameter_definition.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/template_authoring_wizard_dialog.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/dds/dds_template_library_dialog.dart';

void main() {
  group('Template Authoring & Catalog Gallery Tests (Step 4 - SET 13 & 23)', () {
    testWidgets('1. Authoring Wizard navigates all 4 steps and generates valid TemplateParameterDefinition',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      TemplateParameterDefinition? createdTemplate;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => TemplateAuthoringWizardDialog(
                      onTemplateCreated: (t) => createdTemplate = t,
                    ),
                  );
                },
                child: const Text('Open Wizard'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Wizard'));
      await tester.pumpAndSettle();

      expect(find.text('Parametric Template Authoring Wizard'), findsOneWidget);
      expect(find.text('1. Metadata'), findsWidgets);

      await tester.tap(find.text('Next Step'));
      await tester.pumpAndSettle();
      expect(find.text('2. Reference & Ports'), findsWidgets);

      await tester.tap(find.text('Next Step'));
      await tester.pumpAndSettle();
      expect(find.text('3. Parameters & Zones'), findsWidgets);

      await tester.tap(find.text('Next Step'));
      await tester.pumpAndSettle();
      expect(find.text('4. Review & Validate'), findsWidgets);

      await tester.tap(find.text('Save & Instantiate Template'));
      await tester.pumpAndSettle();

      expect(createdTemplate, isNotNull);
      expect(createdTemplate!.templateId, 'custom_tray_tee');
      expect(createdTemplate!.parameters.any((p) => p.name == 'Tray Width'), isTrue);
      expect(createdTemplate!.zoneRules.any((z) => z.id == 'ZONE_RIGID_COUPLERS'), isTrue);
      expect(createdTemplate!.ports.length, 3);
    });

    testWidgets('2. DdsTemplateLibraryDialog renders Stored DSF & Auto-Generated tabs with category filtering',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  DdsTemplateLibraryDialog.show(context);
                },
                child: const Text('Open Gallery'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Gallery'));
      await tester.pumpAndSettle();

      expect(find.text('DSF MASTER TEMPLATE LIBRARY'), findsOneWidget);
      expect(find.text('Stored DSF Files'), findsOneWidget);
      expect(find.text('Auto-Generated Products'), findsOneWidget);

      // Verify category chips
      expect(find.text('All Categories'), findsOneWidget);
      expect(find.text('Cable Ladders'), findsWidgets);
      expect(find.text('Cable Trays'), findsWidgets);
      expect(find.text('Cable Trunking'), findsWidgets);

      // Verify type chips
      expect(find.text('All Types'), findsOneWidget);
      expect(find.text('Straight Lengths'), findsOneWidget);
      expect(find.text('Fittings & Accessories'), findsOneWidget);

      // Switch to Auto-Generated Products Tab
      await tester.tap(find.text('Auto-Generated Products'));
      await tester.pumpAndSettle();

      expect(find.text('Cable Ladder Straight (3000mm)'), findsWidgets);
      expect(find.text('Cable Ladder 90° Horizontal Bend'), findsWidgets);
      expect(find.text('LADDER WIDTH (W)'), findsOneWidget);
      expect(find.text('RAIL HEIGHT (H)'), findsOneWidget);
    });

    testWidgets('3. Auto-Generated Products tab live-updates sliders and opens in CAD Studio',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final vm = SheetMetalStudioViewModel();
      bool openedInCad = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  DdsTemplateLibraryDialog.show(
                    context,
                    viewModel: vm,
                    onOpenInEditor: (doc) {
                      openedInCad = true;
                      vm.loadDocument(doc);
                    },
                  );
                },
                child: const Text('Open Gallery'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Gallery'));
      await tester.pumpAndSettle();

      // Switch to Auto-Generated Products Tab
      await tester.tap(find.text('Auto-Generated Products'));
      await tester.pumpAndSettle();

      // Verify sliders exist
      expect(find.byType(Slider), findsWidgets);
      expect(find.text('LADDER WIDTH (W)'), findsOneWidget);

      // Click Open in CAD Studio
      final openCadFinder = find.text('Open in CAD Studio');
      expect(openCadFinder, findsOneWidget);
      await tester.tap(openCadFinder);
      await tester.pumpAndSettle();

      expect(openedInCad, isTrue);
      expect(vm.document, isNotNull);
      expect(vm.document.productType, 'cable_ladder');
    });
  });
}
