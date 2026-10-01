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
import 'package:trufold_studio/sheet_metal_studio/views/widgets/dds/dds_cms_parameter_inspector.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/dxf_fitting_parameter_dialog.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dxf_fitting_metadata.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_scaling_controller.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/guided_cms/cms_teach_scaling_overlay.dart';
import 'package:trufold_studio/sheet_metal_studio/services/product_catalog_service.dart';

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

    test('5. Catalog Registry provides distinct Equal and Unequal variants for Cross and Tee', () {
      ProductCatalogService.clearCache();

      // Check Tray Accessories
      final trayCrossVars = FittingCatalogRegistry.getVariantNamesForProduct('Tray Accessories', 'Cross');
      expect(trayCrossVars, containsAll(['Equal Cross', 'Unequal Cross']));
      expect(trayCrossVars.contains('Cross'), isFalse);

      final trayTeeVars = FittingCatalogRegistry.getVariantNamesForProduct('Tray Accessories', 'Tee');
      expect(trayTeeVars, containsAll(['Equal Tee', 'Unequal Tee']));
      expect(trayTeeVars.contains('Tee'), isFalse);

      // Check Trunking Accessories
      final trunkingCrossVars = FittingCatalogRegistry.getVariantNamesForProduct('Trunking Accessories', 'Cross');
      expect(trunkingCrossVars, containsAll(['Equal Cross', 'Unequal Cross']));

      final trunkingTeeVars = FittingCatalogRegistry.getVariantNamesForProduct('Trunking Accessories', 'Tee');
      expect(trunkingTeeVars, containsAll(['Equal Tee', 'Unequal Tee']));
    });

    test('6. DxfFittingMetadata detectFromDocument distinguishes Equal vs Unequal variant names', () {
      final equalTeeDoc = DsfDocument.sampleCableTray().copyWith(
        itemName: 'equal_tee_100x100.dsf',
        productType: 'tee',
      );
      final metaEqual = DxfFittingMetadata.detectFromDocument(equalTeeDoc);
      expect(metaEqual.variantName, equals('Equal Tee'));

      final unequalTeeDoc = DsfDocument.sampleCableTray().copyWith(
        itemName: 'unequal_tee_100x100x50x100x100x50x50.dsf',
        productType: 'tee',
      );
      final metaUnequal = DxfFittingMetadata.detectFromDocument(unequalTeeDoc);
      expect(metaUnequal.variantName, equals('Unequal Tee'));

      final equalCrossDoc = DsfDocument.sampleCableTray().copyWith(
        itemName: 'equal_cross_100x100.dsf',
        productType: 'cross',
      );
      final metaCross = DxfFittingMetadata.detectFromDocument(equalCrossDoc);
      expect(metaCross.variantName, equals('Equal Cross'));
    });

    testWidgets('7. CmsTeachScalingOverlay respects selected variant without showing Equal/Unequal toggle bar', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final p1 = const CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 100.0);
      final p2 = const CmsPhysicalPort(id: 'PORT_2', index: 2, width: 100.0, height: 100.0);
      final p3 = const CmsPhysicalPort(id: 'PORT_3', index: 3, width: 100.0, height: 100.0);
      final p4 = const CmsPhysicalPort(id: 'PORT_4', index: 4, width: 100.0, height: 100.0);

      final doc = DsfDocument.sampleCableTray().copyWith(
        productType: 'cross',
        itemName: 'equal_cross_100x100.dsf',
      );

      // --- Equal Cross Fitting ---
      final equalController = CmsScalingController(
        baselineDocument: doc,
        contract: CmsProductContract.equalCross,
        baselinePorts: [p1, p2, p3, p4],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CmsTeachScalingOverlay(
              controller: equalController,
              onAccept: () {},
              onCancel: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Equal variant: Shows Equal Cross Fitting badge and unified Width/Height
      expect(find.text('Equal Cross Fitting'), findsOneWidget);
      expect(find.textContaining('Width (W)'), findsWidgets);
      expect(find.textContaining('Height (H)'), findsWidgets);
      // Suppresses toggle button bar between Equal and Unequal!
      expect(find.text('Equal (Linked)'), findsNothing);
      expect(find.text('Unequal (Independent)'), findsNothing);

      // --- Unequal Cross Fitting ---
      final unequalController = CmsScalingController(
        baselineDocument: doc,
        contract: CmsProductContract.unequalCross,
        baselinePorts: [p1, p2, p3, p4],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CmsTeachScalingOverlay(
              controller: unequalController,
              onAccept: () {},
              onCancel: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Unequal variant: Shows Unequal Cross Fitting badge and Port selector
      expect(find.text('Unequal Cross Fitting'), findsOneWidget);
      expect(find.textContaining('Port 1'), findsWidgets);
      // Suppresses toggle button bar between Equal and Unequal!
      expect(find.text('Equal (Linked)'), findsNothing);
      expect(find.text('Unequal (Independent)'), findsNothing);
    });

    test('8. Product category persistence in DSF document, metadata, and viewmodel save', () {
      final docWithCategory = DsfDocument.sampleCableTray().copyWith(
        metadata: {
          'category': 'Trunking Accessories',
          'fittingCategory': 'Trunking Accessories',
          'product': 'Bend',
          'variantName': '90 Deg Bend',
          'fittingMetadata': {
            'category': 'Trunking Accessories',
            'product': 'Bend',
            'variantName': '90 Deg Bend',
          },
        },
        itemName: '90_deg_bend_100x100.dxf',
      );

      // Verify DsfDocument.category returns Trunking Accessories
      expect(docWithCategory.category, equals('Trunking Accessories'));

      // Verify DxfFittingMetadata.fromDocument preserves Trunking Accessories
      final meta = DxfFittingMetadata.fromDocument(docWithCategory)!;
      expect(meta.category, equals('Trunking Accessories'));

      // Verify DxfFittingMetadata.detectFromDocument checks doc.category first before filename
      final detected = DxfFittingMetadata.detectFromDocument(docWithCategory);
      expect(detected.category, equals('Trunking Accessories'));

      // Verify ViewModel prepareDocumentForSave persists category
      final testVm = SheetMetalStudioViewModel();
      testVm.loadDocument(docWithCategory);
      testVm.updateFittingMetadata(meta);
      final preparedDoc = testVm.prepareDocumentForSave();
      expect(preparedDoc.metadata['category'], equals('Trunking Accessories'));
      expect(preparedDoc.metadata['fittingCategory'], equals('Trunking Accessories'));
      expect((preparedDoc.metadata['fittingMetadata'] as Map)['category'], equals('Trunking Accessories'));
    });

    testWidgets('9. DdsCmsParameterInspector sideways folding arrow button calls onFoldSideways', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      bool folded = false;
      final testVm = SheetMetalStudioViewModel();
      final doc = DsfDocument.sampleCableTray().copyWith(
        productType: 'bend',
        itemName: '90_deg_bend_100x100.dsf',
      );
      testVm.loadDocument(doc);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DdsCmsParameterInspector(
              viewModel: testVm,
              isDetached: false, // Docked mode
              onFoldSideways: () {
                folded = true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the fold arrow button
      final foldBtn = find.byTooltip('Fold / Collapse Sideways');
      expect(foldBtn, findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsWidgets);

      await tester.tap(foldBtn);
      await tester.pumpAndSettle();

      expect(folded, isTrue);
    });

    testWidgets('10. DdsCmsParameterInspector hides Coupler and Bend Radius when category is Trunking Accessories', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final testVm = SheetMetalStudioViewModel();
      final trunkingDoc = DsfDocument.sampleCableTray().copyWith(
        productType: 'bend',
        itemName: 'trunking_90_deg_bend.dsf',
        metadata: {
          'category': 'Trunking Accessories',
          'fittingMetadata': {
            'category': 'Trunking Accessories',
          },
        },
      );
      testVm.loadDocument(trunkingDoc);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DdsCmsParameterInspector(
              viewModel: testVm,
              isDetached: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // For Trunking Accessories:
      // Coupler section must NOT be visible
      expect(find.text('2. COUPLER SLOTS & FLAPS'), findsNothing);
      // Throat Bend Radius must NOT be visible
      expect(find.textContaining('Inside Throat Bend Radius'), findsNothing);
    });

    testWidgets('11. DdsCmsParameterInspector renders Coupler Flap addition button, Bend Radius button and reactive flange direction for Tray Accessories', (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final testVm = SheetMetalStudioViewModel();
      final trayDoc = DsfDocument.sampleCableTray().copyWith(
        productType: 'flatBend90',
        itemName: 'cable_tray_90_deg_bend.dsf',
        metadata: {
          'category': 'Tray Accessories',
          'fittingMetadata': {
            'category': 'Tray Accessories',
          },
        },
      );
      testVm.loadDocument(trayDoc);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DdsCmsParameterInspector(
              viewModel: testVm,
              isDetached: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Coupler section must be visible for Tray Accessories
      expect(find.text('2. COUPLER SLOTS & FLAPS'), findsOneWidget);

      // 2. Coupler Flap Addition Action Button must be visible
      final addFlapBtn = find.textContaining('Add Coupler Flaps');
      expect(addFlapBtn, findsOneWidget);

      // Tap to toggle coupler flaps
      await tester.tap(addFlapBtn);
      await tester.pumpAndSettle();
      expect(find.textContaining('Coupler Flaps Active'), findsOneWidget);

      // 3. Dedicated Bend Radius button and Inside Throat Bend Radius must be visible
      expect(find.text('BEND RADIUS'), findsOneWidget);
      expect(find.textContaining('Inside Throat Bend Radius'), findsOneWidget);

      // 4. Base Flange Direction toggle must be visible and reactive
      final outsideBtn = find.text('Outside Return Flange');
      expect(outsideBtn, findsOneWidget);
      await tester.ensureVisible(outsideBtn);
      await tester.tap(outsideBtn);
      await tester.pumpAndSettle();
      expect(testVm.document.parameters['flange_direction'], equals(1.0));

      final insideBtn = find.text('Inside Flange');
      expect(insideBtn, findsOneWidget);
      await tester.ensureVisible(insideBtn);
      await tester.tap(insideBtn);
      await tester.pumpAndSettle();
      expect(testVm.document.parameters['flange_direction'], equals(0.0));
    });
  });
}

