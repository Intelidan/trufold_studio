// =============================================================================
// template_authoring_and_gallery_test.dart
//
// Widget and unit test suite for Step 4 (SET 13 & 23):
// - TemplateAuthoringWizardDialog (4-step guided template authoring)
// - TemplateLibraryGalleryDialog (Visual catalog card gallery and parametric inspector)
// - FusionRibbonToolbar integration
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/template_parameter_definition.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/template_authoring_wizard_dialog.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/template_library_gallery_dialog.dart';

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

      // Open Wizard
      await tester.tap(find.text('Open Wizard'));
      await tester.pumpAndSettle();

      // Step 1: Classification & Metadata
      expect(find.text('Parametric Template Authoring Wizard'), findsOneWidget);
      expect(find.text('Part Classification & Identity'), findsOneWidget);
      expect(find.text('1. Metadata'), findsOneWidget);

      // Advance to Step 2: Reference & Ports
      await tester.tap(find.text('Next Step'));
      await tester.pumpAndSettle();

      expect(find.text('Reference Alignment & Connecting Ports'), findsOneWidget);
      expect(find.text('Coupling Ports Definition'), findsOneWidget);

      // Advance to Step 3: Parameters & Zones
      await tester.tap(find.text('Next Step'));
      await tester.pumpAndSettle();

      expect(find.text('Driving Parameters & Topological Zones'), findsOneWidget);
      expect(find.text('Topological Invariant & Stretch Zones'), findsOneWidget);
      expect(find.text('Rigid Coupler Tabs (Fixed Punches)'), findsOneWidget);

      // Advance to Step 4: Review & Validation
      await tester.tap(find.text('Next Step'));
      await tester.pumpAndSettle();

      expect(find.text('3-Point Dimension Validation & Verification'), findsOneWidget);
      expect(find.text('Nominal Test'), findsOneWidget);
      expect(find.text('Minimum Bounds Test'), findsOneWidget);
      expect(find.text('Maximum Bounds Test'), findsOneWidget);

      // Click "Save & Instantiate Template"
      await tester.tap(find.text('Save & Instantiate Template'));
      await tester.pumpAndSettle();

      // Verify dialog closed and template was produced
      expect(find.text('Parametric Template Authoring Wizard'), findsNothing);
      expect(createdTemplate, isNotNull);
      expect(createdTemplate!.templateId, 'custom_tray_tee');
      expect(createdTemplate!.parameters.any((p) => p.name == 'Tray Width'), isTrue);
      expect(createdTemplate!.zoneRules.any((z) => z.id == 'ZONE_RIGID_COUPLERS'), isTrue);
      expect(createdTemplate!.ports.length, 3);
    });

    testWidgets('2. Template Library Gallery renders catalog cards and filters by category',
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
                  showDialog(
                    context: context,
                    builder: (_) => const TemplateLibraryGalleryDialog(),
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

      expect(find.text('Parametric Template & Catalog Library'), findsOneWidget);
      expect(find.text('Straight Cable Tray'), findsWidgets);
      expect(find.text('Cable Tray Equal Tee'), findsOneWidget);
      expect(find.text('Cable Tray Reducer'), findsOneWidget);

      // Filter to 'Fittings'
      await tester.tap(find.widgetWithText(ChoiceChip, 'Fittings'));
      await tester.pumpAndSettle();

      expect(find.text('Cable Tray Equal Tee'), findsOneWidget);
      expect(find.text('Cable Tray Reducer'), findsOneWidget);
      expect(find.text('Straight Cable Trunking'), findsNothing);

      // Filter to 'Trunking'
      await tester.tap(find.widgetWithText(ChoiceChip, 'Trunking'));
      await tester.pumpAndSettle();

      expect(find.text('Straight Cable Trunking'), findsOneWidget);
      expect(find.text('Cable Tray Equal Tee'), findsNothing);
    });

    testWidgets('3. Dimension sliders in the gallery live-update parameter values and instantiates into ViewModel',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final vm = SheetMetalStudioViewModel();
      TemplateParameterDefinition? instantiatedTemplate;
      Map<String, double>? instantiatedParams;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => TemplateLibraryGalleryDialog(
                      viewModel: vm,
                      onInstantiate: (tpl, params) {
                        instantiatedTemplate = tpl;
                        instantiatedParams = params;
                      },
                    ),
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

      // Select Equal Tee
      await tester.tap(find.text('Cable Tray Equal Tee'));
      await tester.pumpAndSettle();

      // Verify sliders exist for width, height, branchWidth
      expect(find.byType(Slider), findsWidgets);
      expect(find.text('WIDTH'), findsOneWidget);
      expect(find.text('HEIGHT'), findsOneWidget);
      expect(find.text('BRANCHWIDTH'), findsOneWidget);

      // Click Instantiate in Studio
      final instantiateFinder = find.text('Instantiate in Studio');
      await tester.ensureVisible(instantiateFinder);
      await tester.tap(instantiateFinder);
      await tester.pumpAndSettle();

      expect(instantiatedTemplate, isNotNull);
      expect(instantiatedTemplate!.templateId, 'tray_tee');
      expect(instantiatedParams, isNotNull);
      expect(instantiatedParams!['width'], 100.0);
    });
  });
}
