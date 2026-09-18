// =============================================================================
// branding_3d_icon_and_splash_test.dart
//
// Tests for TruFold 3D Icon, Splash Screen, and App Icon branding components.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/branding/trufold_3d_icon.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/branding/trufold_splash_screen.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/branding/trufold_app_icon_painter.dart';

void main() {
  group('truFold Branding & 3D Icon Tests', () {
    testWidgets('1. TruFold3DIcon renders in static mode at various fold angles without errors', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: const [
                TruFold3DIcon(size: 48, isAnimated: false, fixedFoldAngleDeg: 0.0),   // Flat
                TruFold3DIcon(size: 64, isAnimated: false, fixedFoldAngleDeg: 45.0),  // 45 deg
                TruFold3DIcon(size: 96, isAnimated: false, fixedFoldAngleDeg: 90.0, showAnnotations: true, showGrid: true), // 90 deg
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TruFold3DIcon), findsNWidgets(3));
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('2. TruFold3DIcon animates smoothly as runtime loading indicator', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TruFold3DIcon(size: 80, isAnimated: true),
          ),
        ),
      );

      // Verify widget mounted
      expect(find.byType(TruFold3DIcon), findsOneWidget);

      // Pump 500ms of animation frames
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.hasRunningAnimations, isTrue);
    });

    testWidgets('3. TruFoldSplashScreen executes full animation sequence and triggers completion callback', (tester) async {
      bool completed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: TruFoldSplashScreen(
            totalDuration: const Duration(milliseconds: 1000),
            onInitializationComplete: () {
              completed = true;
            },
          ),
        ),
      );

      expect(find.byType(TruFoldSplashScreen), findsOneWidget);
      expect(find.text('truFold'), findsOneWidget);
      expect(find.text('by danish'), findsOneWidget);
      expect(find.text('STUDIO'), findsOneWidget);

      // Fast forward past totalDuration
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(completed, isTrue);
    });

    testWidgets('4. TruFoldSplashScreen allows tap to skip', (tester) async {
      bool completed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: TruFoldSplashScreen(
            totalDuration: const Duration(milliseconds: 5000),
            allowTapToSkip: true,
            onInitializationComplete: () {
              completed = true;
            },
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));
      expect(completed, isFalse);

      // Tap to skip
      await tester.tap(find.byType(TruFoldSplashScreen));
      await tester.pump();

      expect(completed, isTrue);
    });

    testWidgets('5. TruFoldAppIconTile renders in dark and light mode', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                TruFoldAppIconTile(size: 80, isDark: true),
                TruFoldAppIconTile(size: 80, isDark: false),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TruFoldAppIconTile), findsNWidgets(2));
    });
  });
}
