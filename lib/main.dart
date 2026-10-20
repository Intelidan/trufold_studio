import 'package:flutter/material.dart';

import 'assembly_studio/views/assembly_studio_screen.dart';
import 'sheet_metal_studio/engine/cad_brep_flutter_gpu_scene.dart';
import 'sheet_metal_studio/engine/trufold_3d_engine_preloader.dart';
import 'sheet_metal_studio/theme/studio_theme.dart';
import 'sheet_metal_studio/views/sheet_metal_studio_screen.dart';
import 'sheet_metal_studio/views/widgets/branding/trufold_splash_screen.dart';
import 'sheet_metal_studio/views/widgets/dds/dds_workspace_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  CadWindowsKeyboardGuard.ensureInstalled();
  // Early prewarm of flutter_scene Impeller GPU engine and PBR shaders
  TruFold3dEnginePreloader.instance.preload();
  runApp(const TruFoldStudioApp());
}

class TruFoldStudioApp extends StatefulWidget {
  const TruFoldStudioApp({super.key});

  @override
  State<TruFoldStudioApp> createState() => _TruFoldStudioAppState();
}

class _TruFoldStudioAppState extends State<TruFoldStudioApp> {
  StudioLaunchTarget? _activeStudio;

  Widget _buildActiveStudioScreen() {
    switch (_activeStudio) {
      case StudioLaunchTarget.cad:
        return const SheetMetalStudioScreen();
      case StudioLaunchTarget.assembly:
        return const AssemblyStudioScreen();
      case StudioLaunchTarget.tds:
        return DdsWorkspaceScreen(
          onExit: () {
            setState(() {
              _activeStudio = null;
            });
          },
        );
      case null:
        return TruFoldSplashScreen(
          totalDuration: const Duration(milliseconds: 2800),
          allowTapToSkip: true,
          onLaunchStudio: (target) {
            setState(() {
              _activeStudio = target;
            });
          },
          onInitializationComplete: () {
            setState(() {
              _activeStudio = StudioLaunchTarget.cad;
            });
          },
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TruFold Studio',
      debugShowCheckedModeBanner: false,
      theme: createStudioTheme(),
      home: _buildActiveStudioScreen(),
    );
  }
}
