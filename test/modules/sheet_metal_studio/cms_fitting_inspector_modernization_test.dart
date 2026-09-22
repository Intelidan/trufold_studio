// =============================================================================
// cms_fitting_inspector_modernization_test.dart
//
// Unit & Widget tests for SS1, SS2, and SS3 modernization:
// 1. Stage 7 verified baseline template preservation.
// 2. 2D & 3D Port Annotation visibility toggle.
// 3. Dynamic DSF Fitting Inspector with CmsChannelTopologyPictograph and metrics.
// 4. Teach Scaling (Phase 2) trigger from inspector dialog.
// 5. Suppression of obsolete legacy edge-picking buttons in verified mode.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_physical_port.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_product_contract.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/cms_channel_topology_pictograph.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/dxf_fitting_parameter_dialog.dart';

void main() {
  group('SS1 & SS2: CMS Fitting Inspector Modernization & Port Annotation Toggle', () {
    late SheetMetalStudioViewModel vm;

    setUp(() {
      final port1 = const CmsPhysicalPort(
        id: 'PORT_1',
        index: 1,
        width: 98.0,
        height: 92.0,
        normal: CadPoint3D(0, -1, 0),
      );
      final port2 = const CmsPhysicalPort(
        id: 'PORT_2',
        index: 2,
        width: 98.0,
        height: 92.0,
        normal: CadPoint3D(0.707, -0.707, 0),
      );

      final sampleDoc = DsfDocument.sampleCableTray().copyWith(
        metadata: {
          'category': 'Trunking Accessories',
          'product': 'Bend',
          'variant': '45 Deg Bend',
          'cmsTemplate': {
            'productType': 'bend',
            'variation': '45_deg_bend',
            'ports': [port1.toJson(), port2.toJson()],
          },
        },
      );
      vm = SheetMetalStudioViewModel(initialDocument: sampleDoc);
    });

    test('1. Verified CMS Ports and 2D/3D annotation toggle persistence', () {
      expect(vm.hasVerifiedCmsTemplate, isTrue);
      expect(vm.verifiedCmsPorts.length, equals(2));
      expect(vm.showCmsPortHighlights, isTrue);
      expect(vm.activeCmsPorts.length, equals(2));

      // Toggle port annotations OFF
      vm.toggleCmsPortHighlights();
      expect(vm.showCmsPortHighlights, isFalse);
      // activeCmsPorts hides them for 2D/3D renderers
      expect(vm.activeCmsPorts, isEmpty);
      // But verifiedCmsPorts keeps the template intact!
      expect(vm.verifiedCmsPorts.length, equals(2));
      expect(vm.hasVerifiedCmsTemplate, isTrue);

      // Toggle port annotations back ON
      vm.toggleCmsPortHighlights();
      expect(vm.showCmsPortHighlights, isTrue);
      expect(vm.activeCmsPorts.length, equals(2));
    });

    testWidgets('2. CmsChannelTopologyPictograph renders profile, flow schematic & metrics', (tester) async {
      const port1 = CmsPhysicalPort(
        id: 'PORT_1',
        index: 1,
        width: 98.0,
        height: 92.0,
        normal: CadPoint3D(0, -1, 0),
      );
      const port2 = CmsPhysicalPort(
        id: 'PORT_2',
        index: 2,
        width: 98.0,
        height: 92.0,
        normal: CadPoint3D(0.707, -0.707, 0),
      );

      bool launchTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CmsChannelTopologyPictograph(
                contract: CmsProductContract.bend45,
                ports: const [port1, port2],
                sheetThickness: 1.5,
                flangeMm: 15.0,
                bendCount: 3,
                couplerCount: 8,
                onLaunchTeachScaling: () {
                  launchTapped = true;
                },
              ),
            ),
          ),
        ),
      );

      // Verify header and banner
      expect(find.text('Stage 7: CMS Template Complete & Verified'), findsOneWidget);
      expect(find.text('Teach Scaling (Phase 2) →'), findsOneWidget);
      expect(find.text('CHANNEL TOPOLOGY & FLOW SCHEMATIC (45° Bend)'), findsOneWidget);
      expect(find.text('Mouth Cross-Section'), findsOneWidget);
      expect(find.text('Kinematic Fitting Flow Layout'), findsOneWidget);

      // Verify topological feature chips
      expect(find.text('Floor Web'), findsOneWidget);
      expect(find.text('Sidewalls'), findsOneWidget);
      expect(find.text('Flanges'), findsOneWidget);
      expect(find.text('Coupler Slots'), findsOneWidget);

      // Tap launch button
      await tester.tap(find.text('Teach Scaling (Phase 2) →'));
      expect(launchTapped, isTrue);
    });

    testWidgets('3. DxfFittingParameterDialog renders verified dashboard and suppresses legacy buttons', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DxfFittingParameterDialog(
              viewModel: vm,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Header should show verified status
      expect(find.text('DSF Fitting & Template Inspector'), findsOneWidget);
      expect(find.text('Stage 7 Verified ✓'), findsOneWidget);

      // Annotation toggle button exists
      expect(find.text('Ports (2D/3D): ON'), findsOneWidget);

      // Obsolete legacy buttons MUST NOT exist
      expect(find.text('Auto-Detect from Opening Edge 🎯'), findsNothing);
      expect(find.text('Select W Edge 📏'), findsNothing);
      expect(find.text('Auto-Detect All Ports (1-Click)'), findsNothing);

      // Verified 3D port parameter cards are displayed
      expect(find.text('VERIFIED 3D PHYSICAL PORT PARAMETERS'), findsOneWidget);
      expect(find.text('Port 1 (Inlet / Opening 1)'), findsOneWidget);
      expect(find.text('Port 2 (Outlet / Opening 2)'), findsOneWidget);

      // Teach Scaling (Phase 2) button in bottom bar
      expect(find.widgetWithText(ElevatedButton, 'Teach Scaling (Phase 2) →'), findsWidgets);

      // Tap Ports (2D/3D) toggle button
      await tester.tap(find.text('Ports (2D/3D): ON'));
      await tester.pumpAndSettle();
      expect(vm.showCmsPortHighlights, isFalse);
      expect(find.text('Ports (2D/3D): OFF'), findsOneWidget);
    });

    testWidgets('4. Declaring non-CMS drawing as CMS Product in DSF Fitting Inspector enables CMS product contract and launches discovery', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Create a plain non-CMS document
      final nonCmsDoc = DsfDocument.sampleCableTray().copyWith(
        itemName: 'custom_fitting.dxf',
        productType: 'None',
        metadata: {},
      );

      final plainVm = SheetMetalStudioViewModel(initialDocument: nonCmsDoc);
      expect(plainVm.isCmsDrawing, isFalse);
      expect(plainVm.hasVerifiedCmsTemplate, isFalse);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DxfFittingParameterDialog(
              viewModel: plainVm,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Dialog shows DSF Fitting Inspector for unverified drawing
      expect(find.text('DSF Fitting Inspector'), findsOneWidget);
      expect(find.text('Declare as CMS Product Fitting'), findsOneWidget);
      expect(find.text('Declare as CMS Product & Discover 3D →'), findsOneWidget);
      expect(find.text('Save Parameters to DSF'), findsOneWidget);

      // Tap Declare as CMS Product & Discover 3D
      await tester.tap(find.text('Declare as CMS Product & Discover 3D →'));
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      // Document is now recognized as CMS Product
      expect(plainVm.isCmsDrawing, isTrue);
      expect(plainVm.document.metadata['isCmsProduct'], isTrue);
      expect(plainVm.document.metadata['cmsWorkflow']?['stage'], 'manufacturing_definition');
    });
  });
}
