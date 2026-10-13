import 'package:flutter/material.dart';
import 'views/assembly_studio_screen.dart';

/// Standalone Executable Entry Point for TruFold 3D Assembly Studio.
/// Can be run directly:
/// `flutter run -t lib/assembly_studio/main_assembly_studio.dart -d windows`
/// Or built into a separate executable:
/// `flutter build windows -t lib/assembly_studio/main_assembly_studio.dart`
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AssemblyStudioApp());
}

class AssemblyStudioApp extends StatelessWidget {
  const AssemblyStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TruFold 3D Assembly Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light().copyWith(
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF0284C7),
          secondary: Color(0xFF0369A1),
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
        ),
        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(4),
          ),
          textStyle: const TextStyle(fontSize: 10, color: Colors.white),
        ),
      ),
      home: const AssemblyStudioScreen(),
    );
  }
}
