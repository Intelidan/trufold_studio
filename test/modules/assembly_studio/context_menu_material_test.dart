import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/assembly_studio/viewmodels/assembly_studio_viewmodel.dart';
import 'package:trufold_studio/assembly_studio/models/assembly_part.dart';
import 'package:trufold_studio/assembly_studio/views/widgets/viewport/overlays/assembly_viewport_dialogs.dart';
import 'package:trufold_studio/assembly_studio/views/widgets/assembly_3d_viewport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AssemblyStudioViewModel viewModel;

  setUp(() {
    viewModel = AssemblyStudioViewModel();
    viewModel.addPart(
      AssemblyPart(
        id: 'rail_test_1',
        name: 'Rail 1',
        type: AssemblyPartType.straightRail,
        length: 500.0,
        height: 100.0,
      ),
    );
  });

  group('Right-Click Context Menu & Canvas Material Ancestor Tests', () {
    testWidgets('showContextMenu with selection renders InkWell with Material ancestor and handles taps', (tester) async {
      viewModel.selectPart('rail_test_1');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () {
                    AssemblyViewportDialogs.showContextMenu(
                      ctx,
                      const Offset(100, 100),
                      viewModel,
                      onZoomToFit: () {},
                      onPromptGroupNameAndGroup: () async {},
                    );
                  },
                  child: const Text('Open Context Menu'),
                ),
              ),
            ),
          ),
        ),
      );

      // Open context menu dialog
      await tester.tap(find.text('Open Context Menu'));
      await tester.pumpAndSettle();

      // Verify the menu items are present
      expect(find.text('Duplicate'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Clear Selection'), findsOneWidget);

      // Tap 'Duplicate' — must not throw "No Material widget found"
      await tester.tap(find.text('Duplicate'));
      await tester.pumpAndSettle();

      // Dialog should be dismissed
      expect(find.text('Duplicate'), findsNothing);
    });

    testWidgets('showContextMenu on empty canvas renders Select All & Zoom to Fit and taps cleanly', (tester) async {
      viewModel.selectPart(null);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () {
                    AssemblyViewportDialogs.showContextMenu(
                      ctx,
                      const Offset(200, 200),
                      viewModel,
                      onZoomToFit: () {},
                      onPromptGroupNameAndGroup: () async {},
                    );
                  },
                  child: const Text('Open Empty Context Menu'),
                ),
              ),
            ),
          ),
        ),
      );

      // Open context menu
      await tester.tap(find.text('Open Empty Context Menu'));
      await tester.pumpAndSettle();

      expect(find.text('Select All'), findsOneWidget);
      expect(find.text('Zoom to Fit'), findsOneWidget);

      // Tap 'Zoom to Fit' — should dismiss without any exception
      await tester.tap(find.text('Zoom to Fit'));
      await tester.pumpAndSettle();

      expect(find.text('Zoom to Fit'), findsNothing);
    });

    testWidgets('Assembly3DViewport contextual banners (Bridge, Weld, Magnet) render InkWell controls with Material ancestor', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 700,
              child: Assembly3DViewport(viewModel: viewModel),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Activate Weld Tool -> Shows Weld Tool Banner
      viewModel.setToolMode(SketchUpToolMode.weld);
      await tester.pumpAndSettle();

      expect(find.textContaining('Weld Tool: Click and drag'), findsOneWidget);

      // Tap close button on the weld banner (InkWell)
      final weldBannerRow = find.ancestor(
        of: find.textContaining('Weld Tool: Click and drag'),
        matching: find.byType(Row),
      );
      final closeBtn = find.descendant(
        of: weldBannerRow,
        matching: find.byType(InkWell),
      );
      expect(closeBtn, findsOneWidget);
      await tester.tap(closeBtn);
      await tester.pumpAndSettle();

      // Tool mode switches back to select
      expect(viewModel.activeToolMode, equals(SketchUpToolMode.select));

      // 2. Activate Bridge Tool -> Shows Auto-Span Bridge Banner
      viewModel.setToolMode(SketchUpToolMode.bridge);
      await tester.pumpAndSettle();

      expect(find.textContaining('Auto-Span Bridge'), findsOneWidget);

      // Tap close button on the bridge banner
      final bridgeBannerRow = find.ancestor(
        of: find.textContaining('Auto-Span Bridge'),
        matching: find.byType(Row),
      );
      final bridgeCloseBtn = find.descendant(
        of: bridgeBannerRow,
        matching: find.byType(InkWell),
      );
      expect(bridgeCloseBtn, findsOneWidget);
      await tester.tap(bridgeCloseBtn);
      await tester.pumpAndSettle();

      expect(viewModel.activeToolMode, equals(SketchUpToolMode.select));
    });
  });
}
