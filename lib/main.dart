import 'package:flutter/material.dart';
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
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0284C7),
          brightness: Brightness.light,
        ),
      ),
      home: const SheetMetalStudioScreen(),
    );
  }
}
