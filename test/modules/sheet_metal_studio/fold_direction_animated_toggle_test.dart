import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/fold_bend_line.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/fold_direction_animated_toggle.dart';

void main() {
  group('FoldDirectionAnimatedToggle', () {
    testWidgets('Renders +Z UP state correctly and toggles to -Z DOWN on tap', (tester) async {
      BendDirection currentDir = BendDirection.up;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                child: StatefulBuilder(
                  builder: (context, setState) {
                    return FoldDirectionAnimatedToggle(
                      direction: currentDir,
                      onToggle: (newDir) {
                        setState(() {
                          currentDir = newDir;
                        });
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );

      // Verify +Z UP state
      expect(find.text('↑ (+Z) UP'), findsOneWidget);
      expect(find.text('SURFACE ▲ (Toward Viewer)'), findsOneWidget);

      // Tap toggle
      await tester.tap(find.byType(FoldDirectionAnimatedToggle));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      // Verify toggled to -Z DOWN
      expect(currentDir, BendDirection.down);
      expect(find.text('↓ (-Z) DOWN'), findsOneWidget);
      expect(find.text('REVERSE ▼ (Into Screen)'), findsOneWidget);

      // Tap again to toggle back to +Z UP
      await tester.tap(find.byType(FoldDirectionAnimatedToggle));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(currentDir, BendDirection.up);
      expect(find.text('↑ (+Z) UP'), findsOneWidget);
    });
  });
}
