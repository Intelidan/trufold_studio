import 'package:flutter/material.dart';

import 'sheet_metal_studio/theme/studio_theme.dart';
import 'sheet_metal_studio/views/sheet_metal_studio_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TruFoldStudioApp());
}

class TruFoldStudioApp extends StatelessWidget {
  const TruFoldStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TruFold Studio',
      debugShowCheckedModeBanner: false,
      theme: createStudioTheme(),
      home: const SheetMetalStudioScreen(),
    );
  }
}
