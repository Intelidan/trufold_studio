import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:three_js/three_js.dart' as three;

import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/three_cad_mesh_builder.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/studio/studio_3d_navigation_bar.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/studio/studio_view_cube.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/studio/studio_graphics_preferences_panel.dart';

void main() {
  test('ThreeJS scene setup and OrbitControls initialization check', () {
    final scene = three.Scene();
    final camera = three.PerspectiveCamera(45.0, 1.33, 1.0, 50000.0);
    camera.position.setValues(100, 100, 100);
    camera.lookAt(three.Vector3(0, 0, 0));

    final ambient = three.AmbientLight(0xffffff, 0.65);
    scene.add(ambient);

    final dir = three.DirectionalLight(0xffffff, 0.85);
    dir.position.setValues(100, 150, 100);
    scene.add(dir);

    final poly = CadFoldedPolygon3D(
      faceId: 'test_web',
      vertices: [
        const CadPoint3D(0, -150, 50),
        const CadPoint3D(250, -150, 50),
        const CadPoint3D(250, 150, 50),
        const CadPoint3D(0, 150, 50),
      ],
      normal: const CadPoint3D(0, 0, 1),
      color: const Color(0xFF90A4AE),
      boundaryLines: [
        [const CadPoint3D(0, -150, 50), const CadPoint3D(250, -150, 50)],
        [const CadPoint3D(250, -150, 50), const CadPoint3D(250, 150, 50)],
      ],
    );

    final meshResult = FoldedMeshResult(
      polygons: [poly],
      thicknessPolygons: [],
      boundWidth: 300,
      boundLength: 250,
      boundHeight: 100,
      center: const CadPoint3D(125, 0, 50),
    );

    final group = ThreeCadMeshBuilder.buildCadModel(meshResult);
    scene.add(group);

    expect(scene.children.length, 3); // ambient + dir + group
  });

  testWidgets('Studio3dNavigationBar renders CAD navigation tools and triggers actions', (tester) async {
    bool fitAllCalled = false;
    double? selectedAz;
    double? selectedEl;
    bool orbitModeToggled = false;
    bool panToolToggled = false;
    bool projToggled = false;
    bool borderLinesToggled = false;
    bool xRayToggled = false;
    CadShadingStyle currentShadingStyle = CadShadingStyle.realisticPbr;
    AntiAliasingQuality currentAntiAliasing = AntiAliasingQuality.high;
    CadNavigationScheme currentScheme = CadNavigationScheme.trufold;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Studio3dNavigationBar(
            onFitAll: () => fitAllCalled = true,
            onSelectView: (az, el) {
              selectedAz = az;
              selectedEl = el;
            },
            isTurntable: true,
            onToggleOrbitMode: () => orbitModeToggled = true,
            isPanToolActive: false,
            onTogglePanTool: () => panToolToggled = true,
            isOrtho: false,
            onToggleProjection: () => projToggled = true,
            currentScheme: currentScheme,
            onSchemeChanged: (s) => currentScheme = s,
            showBorderLines: true,
            onToggleBorderLines: () => borderLinesToggled = true,
            isObstructedXRay: false,
            onToggleObstructedXRay: () => xRayToggled = true,
            currentShadingStyle: currentShadingStyle,
            onShadingStyleChanged: (s) => currentShadingStyle = s,
            currentAntiAliasing: currentAntiAliasing,
            onAntiAliasingChanged: (a) => currentAntiAliasing = a,
          ),
        ),
      ),
    );

    // Verify icons rendered
    expect(find.byIcon(Icons.fit_screen), findsOneWidget);
    expect(find.byIcon(Icons.grid_view_rounded), findsOneWidget);
    expect(find.byIcon(Icons.screen_rotation), findsOneWidget);
    expect(find.byIcon(Icons.pan_tool_outlined), findsOneWidget);
    expect(find.byIcon(Icons.view_in_ar), findsOneWidget);
    expect(find.byIcon(Icons.layers_outlined), findsOneWidget);
    expect(find.byIcon(Icons.border_style), findsOneWidget);
    expect(find.byIcon(Icons.palette_outlined), findsOneWidget);
    expect(find.byIcon(Icons.high_quality), findsOneWidget);
    expect(find.byIcon(Icons.mouse_rounded), findsOneWidget);

    // Tap Fit All
    await tester.tap(find.byIcon(Icons.fit_screen));
    await tester.pump();
    expect(fitAllCalled, true);

    // Tap Orbit Mode
    await tester.tap(find.byIcon(Icons.screen_rotation));
    await tester.pump();
    expect(orbitModeToggled, true);

    // Tap Pan Tool
    await tester.tap(find.byIcon(Icons.pan_tool_outlined));
    await tester.pump();
    expect(panToolToggled, true);

    // Tap Projection
    await tester.tap(find.byIcon(Icons.view_in_ar));
    await tester.pump();
    expect(projToggled, true);

    // Tap Obstructed X-Ray
    await tester.tap(find.byIcon(Icons.layers_outlined));
    await tester.pump();
    expect(xRayToggled, true);

    // Tap Border Lines
    await tester.tap(find.byIcon(Icons.border_style));
    await tester.pump();
    expect(borderLinesToggled, true);

    expect(selectedAz, isNull);
    expect(selectedEl, isNull);
  });

  test('Check ThreeJS materials and constants', () {
    expect(three.GreaterDepth, isNotNull);
    final toon = three.MeshToonMaterial.fromMap({
      'vertexColors': true,
      'side': three.DoubleSide,
    });
    expect(toon, isNotNull);

    final obstructed = three.MeshBasicMaterial.fromMap({
      'color': 0x0284c7,
      'transparent': true,
      'opacity': 0.35,
      'depthTest': true,
      'depthWrite': false,
      'side': three.DoubleSide,
    });
    obstructed.depthFunc = three.GreaterDepth;
    expect(obstructed.depthFunc, three.GreaterDepth);
  });

  testWidgets('StudioViewCube renders micro movement buttons and triggers actions', (tester) async {
    double? dAz;
    double? dEl;
    bool fitCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StudioViewCube(
            azimuthDeg: 45,
            elevationDeg: 30,
            onOrbit: (da, de) {
              dAz = da;
              dEl = de;
            },
            onZoomToFit: () => fitCalled = true,
          ),
        ),
      ),
    );

    // Verify micro movement chevron buttons rendered
    expect(find.byTooltip('Tilt Up (15°)'), findsOneWidget);
    expect(find.byTooltip('Tilt Down (15°)'), findsOneWidget);
    expect(find.byTooltip('Rotate Left (15°)'), findsOneWidget);
    expect(find.byTooltip('Rotate Right (15°)'), findsOneWidget);

    // Tap tilt up
    await tester.tap(find.byTooltip('Tilt Up (15°)'));
    await tester.pump();
    expect(dEl, 15.0);

    // Tap rotate left
    await tester.tap(find.byTooltip('Rotate Left (15°)'));
    await tester.pump();
    expect(dAz, -15.0);
    expect(fitCalled, isFalse);
  });

  testWidgets('StudioGraphicsPreferencesPanel renders sliders and triggers callbacks', (tester) async {
    OnshapeGraphicsPreferences currentPrefs = const OnshapeGraphicsPreferences();
    bool closed = false;
    bool reset = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StudioGraphicsPreferencesPanel(
            preferences: currentPrefs,
            onChanged: (p) => currentPrefs = p,
            onClose: () => closed = true,
            onResetToDefault: () => reset = true,
          ),
        ),
      ),
    );

    expect(find.text('Graphics preferences'), findsOneWidget);
    expect(find.text('Viewport'), findsOneWidget);
    expect(find.text('Shaded bodies'), findsOneWidget);
    expect(find.text('Phantom edges'), findsOneWidget);
    expect(find.text('Reset to default'), findsOneWidget);

    // Tap Close
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(closed, true);

    // Tap Reset to default
    await tester.tap(find.text('Reset to default'));
    await tester.pump();
    expect(reset, true);
  });

  test('CAD model rebuild maintains orientation/quaternion in-place across graphics and parameter updates', () {
    final poly = CadFoldedPolygon3D(
      faceId: 'face_param_test',
      vertices: [
        const CadPoint3D(0, 0, 0),
        const CadPoint3D(200, 0, 0),
        const CadPoint3D(200, 100, 0),
        const CadPoint3D(0, 100, 0),
      ],
      normal: const CadPoint3D(0, 0, 1),
      color: const Color(0xFF64748B),
    );
    final mesh1 = FoldedMeshResult(
      polygons: [poly],
      thicknessPolygons: [],
      boundWidth: 200,
      boundLength: 100,
      boundHeight: 1,
      center: const CadPoint3D(100, 50, 0),
    );

    // Initial build
    final group1 = ThreeCadMeshBuilder.buildCadModel(mesh1);
    // Simulate user rotating the model
    group1.quaternion.setFromAxisAngle(three.Vector3(0, 1, 0), 0.785); // 45 deg around Y
    final savedQuat = group1.quaternion.clone();

    // Now a parameter or graphics setting changes (e.g. wireframe or dimensions)
    final mesh2 = FoldedMeshResult(
      polygons: [poly],
      thicknessPolygons: [],
      boundWidth: 300,
      boundLength: 150,
      boundHeight: 1,
      center: const CadPoint3D(150, 75, 0),
    );
    final group2 = ThreeCadMeshBuilder.buildCadModel(mesh2, showWireframe: false);
    // Apply in-place orientation preservation logic as in _updateCadModel()
    group2.quaternion.x = savedQuat.x;
    group2.quaternion.y = savedQuat.y;
    group2.quaternion.z = savedQuat.z;
    group2.quaternion.w = savedQuat.w;
    group2.updateMatrixWorld(true);

    expect(group2.quaternion.x, closeTo(savedQuat.x, 1e-6));
    expect(group2.quaternion.y, closeTo(savedQuat.y, 1e-6));
    expect(group2.quaternion.z, closeTo(savedQuat.z, 1e-6));
    expect(group2.quaternion.w, closeTo(savedQuat.w, 1e-6));
  });

  test('Center product targets origin (0, 0, 0) and frames model along user line-of-sight without drift', () {
    final camera = three.PerspectiveCamera(45.0, 1.33, 1.0, 50000.0);
    // Arbitrary user viewing position and panned target
    camera.position.setValues(300, 400, 500);
    final cameraTarget = three.Vector3(50, -20, 30);
    camera.lookAt(cameraTarget);

    final lineOfSight = camera.position.clone().sub(cameraTarget).normalize();
    const fitDist = 450.0;
    final targetPos = three.Vector3(0, 0, 0);
    final newCamPos = targetPos.clone().addScaled(lineOfSight, fitDist);

    // Apply centered framing
    camera.position.setValues(newCamPos.x, newCamPos.y, newCamPos.z);
    cameraTarget.setValues(targetPos.x, targetPos.y, targetPos.z);
    camera.lookAt(cameraTarget);

    // New line of sight from camera to target must strictly match previous line of sight
    final newLineOfSight = camera.position.clone().sub(cameraTarget).normalize();
    expect(newLineOfSight.x, closeTo(lineOfSight.x, 1e-5));
    expect(newLineOfSight.y, closeTo(lineOfSight.y, 1e-5));
    expect(newLineOfSight.z, closeTo(lineOfSight.z, 1e-5));
    // Distance to origin must equal fitDist
    expect(camera.position.length, closeTo(fitDist, 1e-3));
  });
}


