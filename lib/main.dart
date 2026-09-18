import 'package:flutter/material.dart';

import 'sheet_metal_studio/theme/studio_theme.dart';
import 'sheet_metal_studio/views/sheet_metal_studio_screen.dart';
import 'sheet_metal_studio/views/widgets/branding/trufold_splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TruFoldStudioApp());
}

class TruFoldStudioApp extends StatefulWidget {
  const TruFoldStudioApp({super.key});

  @override
  State<TruFoldStudioApp> createState() => _TruFoldStudioAppState();
}

class _TruFoldStudioAppState extends State<TruFoldStudioApp> {
  bool _initialized = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TruFold Studio',
      debugShowCheckedModeBanner: false,
      theme: createStudioTheme(),
      home: _initialized
          ? const SheetMetalStudioScreen()
          : TruFoldSplashScreen(
              totalDuration: const Duration(milliseconds: 3200),
              allowTapToSkip: false,
              onInitializationComplete: () {
                setState(() {
                  _initialized = true;
                });
              },
            ),
    );
  }
}
