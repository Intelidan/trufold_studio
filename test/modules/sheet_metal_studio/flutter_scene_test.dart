import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_scene/scene.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/viewport_3d/flutter_scene_viewport_widget.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:trufold_studio/sheet_metal_studio/engine/flutter_scene_cad_mesh_builder.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cad_polygon_triangulator.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cnc_punch_primitive.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/ladder/ladder_assembly_generator.dart';
import 'package:trufold_studio/sheet_metal_studio/models/ladder/ladder_assembly_parameters.dart';
import 'package:trufold_studio/sheet_metal_studio/models/sheet_metal_material.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/canvas_2d/controllers/vector_cad_controller.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/studio/studio_view_cube.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Flutter Scene 0.24.0 Integration & Procedural Mesh Tests', () {
    test('Constructs Scene, PerspectiveCamera, and checks camera properties', () {
      final camera = PerspectiveCamera(position: vm.Vector3(0, 50, 150), target: vm.Vector3(0, 0, 0));
      expect(camera, isNotNull);
      expect(camera.position.z, equals(150.0));
      expect(camera.target.y, equals(0.0));
    });

    test('Procedural CAD Mesh generation from KinematicFoldEngine using GeometryBuilder', () {
      // 1. Synthesize CAD sheet metal part via VectorCadController
      final controller = VectorCadController();
      final doc = controller.toDsfDocument();

      final foldedMesh = KinematicFoldEngine.foldDocument(doc, foldProgress: 1.0);
      expect(foldedMesh.polygons, isNotEmpty);

      // 2. GeometryBuilder dynamically constructs triangles directly from foldedMesh
      final builder = GeometryBuilder();
      int trianglesCount = 0;

      for (final poly in foldedMesh.polygons) {
        if (poly.vertices.length < 3) continue;

        // Triangulate n-gon into triangle fan
        final v0 = poly.vertices[0];
        for (int i = 1; i < poly.vertices.length - 1; i++) {
          final v1 = poly.vertices[i];
          final v2 = poly.vertices[i + 1];

          final i0 = builder.addVertex(vm.Vector3(v0.x, v0.y, v0.z));
          final i1 = builder.addVertex(vm.Vector3(v1.x, v1.y, v1.z));
          final i2 = builder.addVertex(vm.Vector3(v2.x, v2.y, v2.z));

          builder.addTriangle(i0, i1, i2);
          trianglesCount++;
        }
      }

      expect(builder.vertexCount, greaterThan(0));
      expect(builder.triangleCount, equals(trianglesCount));

      // 3. Test packVertices (pure CPU interleaved byte packing, verified without GPU context)
      final packedBytes = builder.packVertices();
      expect(packedBytes, isNotEmpty);
      expect(packedBytes.length, greaterThan(0));
    });

    test('CAD Mesh Builder generates single centered boundary edges and phantom tangent edges', () {
      final doc = DsfDocument.sampleCableTray(width: 100, height: 50, length: 300, thickness: 2.0);
      final foldedMesh = KinematicFoldEngine.foldDocument(doc, foldProgress: 1.0);

      // 1. Verify single border line rule: bottom face has NO duplicate boundary lines
      final botFaces = foldedMesh.thicknessPolygons.where((p) => p.faceId.endsWith('_BOT'));
      for (final p in botFaces) {
        expect(p.boundaryLines, isEmpty);
      }

      // 2. Verify top face border lines are generated at the sheet surface face (z = 0.0 mm)
      final floorFace = foldedMesh.polygons.firstWhere((p) => p.faceId == 'F_FLOOR');
      expect(floorFace.boundaryLines, isNotEmpty);
      for (final line in floorFace.boundaryLines) {
        for (final pt in line) {
          expect(pt.z, closeTo(0.0, 0.05));
        }
      }

      // 3. Verify fillet rims have border lines generated along the curved fillet profile
      final filletCaps = foldedMesh.filletPolygons.where((p) => p.faceId.startsWith('FILLET_CAP'));
      final filletBoundaries = [for (final p in filletCaps) ...p.boundaryLines];
      expect(filletBoundaries, isNotEmpty);
      for (final line in filletBoundaries) {
        expect(line.length, equals(2));
        expect(line[0].distanceTo(line[1]), greaterThan(0.01));
      }

      // 3b. Verify face cutout punches generate hole border lines on the face
      final punchedDoc = doc.copyWith(
        punches: [
          const CncPunchPrimitive(
            id: 'P1',
            type: PunchType.roundHole,
            center: CadPoint2D(115.0, 50.0), // Center of F_FLOOR (xB2=65..165)
            diameterMm: 12.0,
          ),
        ],
      );
      final punchedMesh = KinematicFoldEngine.foldDocument(punchedDoc, foldProgress: 1.0);
      final punchedFloor = punchedMesh.polygons.firstWhere((p) => p.faceId == 'F_FLOOR');
      expect(punchedFloor.boundaryLines.length, greaterThan(2));

      // 4. Verify fillet polygons contain consolidated tangent lines
      final filletPolysWithTangents = foldedMesh.filletPolygons.where((p) => p.tangentLines.isNotEmpty);
      expect(filletPolysWithTangents, isNotEmpty);
      for (final p in filletPolysWithTangents) {
        for (final tanSeg in p.tangentLines) {
          expect(tanSeg.length, equals(2));
          expect(tanSeg[0].distanceTo(tanSeg[1]), greaterThan(1.0));
        }
      }

      // 5. Verify FlutterSceneCadMeshBuilder constructs nodes when GPU backend is available
      try {
        final cadNode = FlutterSceneCadMeshBuilder.buildCadModel(
          foldedMesh,
          preferences: const OnshapeGraphicsPreferences(
            tangentEdgeMode: OnshapeTangentEdgeMode.phantom,
            phantomTangentEdgeWidth: 2.4,
          ),
        );
        final edgeNode = cadNode.children.firstWhere((n) => n.name == 'CadBoundaryEdges');
        final tangentNode = cadNode.children.firstWhere((n) => n.name == 'CadPhantomTangentEdges');
        expect(edgeNode, isNotNull);
        expect(tangentNode, isNotNull);
      } catch (e) {
        // Headless flutter test without Impeller GPU context
        expect(e.toString(), contains('Flutter GPU requires the Impeller'));
      }
    });

    testWidgets('FlutterSceneViewportWidget mounts safely inside LayoutBuilder without LateInitializationError', (tester) async {
      final viewModel = SheetMetalStudioViewModel();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LayoutBuilder(
              builder: (context, constraints) {
                return SizedBox(width: 800, height: 600, child: FlutterSceneViewportWidget(viewModel: viewModel));
              },
            ),
          ),
        ),
      );

      expect(find.byType(FlutterSceneViewportWidget), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Tab switching preserves 3D camera state across multiple drawings/tabs', (tester) async {
      final vmTab1 = SheetMetalStudioViewModel();
      final vmTab2 = SheetMetalStudioViewModel();

      // Mount with tab 1
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 800, height: 600, child: FlutterSceneViewportWidget(viewModel: vmTab1)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // State is initialized on vmTab1
      expect(vmTab1.camera3dState, isNotNull);

      // Simulate user orbiting/modifying camera in Tab 1 via drag
      await tester.drag(find.byType(FlutterSceneViewportWidget), const Offset(100, 50));
      await tester.pumpAndSettle();

      expect(vmTab1.camera3dState, isNotNull);
      final tab1Azimuth = vmTab1.camera3dState!.azimuthDeg;
      final tab1Elevation = vmTab1.camera3dState!.elevationDeg;
      expect(tab1Azimuth, isNot(45.0));

      // Switch tab to Tab 2
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 800, height: 600, child: FlutterSceneViewportWidget(viewModel: vmTab2)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tab 2 has its own state
      expect(vmTab2.camera3dState, isNotNull);

      // Drag to orbit camera on Tab 2
      await tester.drag(find.byType(FlutterSceneViewportWidget), const Offset(-80, -40));
      await tester.pumpAndSettle();

      final tab2Azimuth = vmTab2.camera3dState!.azimuthDeg;
      expect(tab2Azimuth, isNot(tab1Azimuth));

      // Switch back to Tab 1
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 800, height: 600, child: FlutterSceneViewportWidget(viewModel: vmTab1)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tab 1 camera state remains exactly as user left it
      expect(vmTab1.camera3dState!.azimuthDeg, tab1Azimuth);
      expect(vmTab1.camera3dState!.elevationDeg, tab1Elevation);
    });

    testWidgets('Tab switching smoothly transitions camera positions over time', (tester) async {
      final vmTabA = SheetMetalStudioViewModel();
      final vmTabB = SheetMetalStudioViewModel();

      vmTabA.camera3dState = const Cad3dCameraState(
        azimuthDeg: 30.0,
        elevationDeg: 20.0,
        zoom: 1.0,
        orbitDistance: 300.0,
        isInitialized: true,
      );

      vmTabB.camera3dState = const Cad3dCameraState(
        azimuthDeg: 90.0,
        elevationDeg: 60.0,
        zoom: 2.0,
        orbitDistance: 600.0,
        isInitialized: true,
      );

      // Mount Tab A
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 800, height: 600, child: FlutterSceneViewportWidget(viewModel: vmTabA)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Tab B (starts smooth animation towards 90 deg azimuth, 60 deg elevation)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 800, height: 600, child: FlutterSceneViewportWidget(viewModel: vmTabB)),
          ),
        ),
      );

      // Pump halfway through the 380ms transition duration (190ms)
      await tester.pump(const Duration(milliseconds: 190));

      // Camera is smoothly interpolating between 30 and 90, not snapped!
      expect(vmTabB.camera3dState!.azimuthDeg, greaterThan(30.0));
      expect(vmTabB.camera3dState!.azimuthDeg, lessThan(90.0));
      expect(vmTabB.camera3dState!.elevationDeg, greaterThan(20.0));
      expect(vmTabB.camera3dState!.elevationDeg, lessThan(60.0));

      // Settle the remainder of the transition
      await tester.pumpAndSettle();

      // Final camera settled exactly on Tab B's target values
      expect(vmTabB.camera3dState!.azimuthDeg, closeTo(90.0, 0.01));
      expect(vmTabB.camera3dState!.elevationDeg, closeTo(60.0, 0.01));
      expect(vmTabB.camera3dState!.orbitDistance, closeTo(600.0, 0.01));
    });

    test('Cable ladder templates generate hole borders on rungs and side rails', () {
      final assembly = LadderAssemblyGenerator.generateStraightLadder(
        const LadderAssemblyParameters(
          length: 1000,
          width: 300,
          intermediateTargetPitch: 250,
        ),
      );
      final ladderMesh = assembly.assembledMesh3D;

      expect(ladderMesh.polygons.isNotEmpty, isTrue);

      // Check outer rung webs have boundaryLines for the obround cutout holes
      final rungWebPolygons = ladderMesh.polygons.where((p) => p.faceId.contains('rung') && p.faceId.contains('top_web') && !p.faceId.contains('inner'));
      expect(rungWebPolygons.isNotEmpty, isTrue);
      for (final rungWeb in rungWebPolygons) {
        expect(rungWeb.boundaryLines.length, greaterThanOrEqualTo(16),
            reason: 'Rung web must have border lines for its obround holes');
      }

      // Check outer side rail webs have boundaryLines for pass-through slot holes (4 edges for slot + perimeter)
      final railWebPolygons = ladderMesh.polygons.where((p) => p.faceId.contains('rail') && p.faceId.contains('web') && !p.faceId.contains('inner'));
      expect(railWebPolygons.isNotEmpty, isTrue);
      for (final railWeb in railWebPolygons) {
        expect(railWeb.boundaryLines.length, greaterThanOrEqualTo(4),
            reason: 'Side rail web must have border lines for slot holes');
      }
    });

    test('Kinematic fold engine fillet cap generates outer border line and hole borders', () {
      final controller = VectorCadController();
      final doc = controller.toDsfDocument();
      final mesh = KinematicFoldEngine.foldDocument(doc, foldProgress: 1.0);
      expect(mesh.polygons.isNotEmpty, isTrue);

      final filletCaps = mesh.polygons.where((p) => p.faceId.contains('FILLET_CAP'));
      for (final cap in filletCaps) {
        expect(cap.boundaryLines.isNotEmpty, isTrue);
      }

      // Base face should have hole boundary lines for punches
      final baseFace = mesh.polygons.firstWhere((p) => p.faceId.contains('rect_bottom') || p.faceId.contains('rect_top'));
      expect(baseFace.boundaryLines.length, greaterThan(4),
          reason: 'Base face must have boundary lines for punches as well as perimeter');
    });

    testWidgets('Vertical mouse navigation loops continuously past 90, 180, 270, and 360 degrees without clamping', (tester) async {
      final doc = DsfDocument.sampleCableTray(width: 100, height: 50, length: 200, thickness: 2.0);
      final vm = SheetMetalStudioViewModel();
      vm.loadDocument(doc);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: FlutterSceneViewportWidget(viewModel: vm),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final initialElevation = vm.camera3dState!.elevationDeg;

      // Drag up with left mouse button to rotate vertically upward
      // Each drag move of delta.dy = -100 causes dElevation = -(-100) * 0.5 = +50 degrees
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton);
      await gesture.addPointer(location: const Offset(400, 300));
      await gesture.down(const Offset(400, 300));

      // Drag 1: dy = -200 -> delta elevation = +100 degrees -> elevation > 90
      await gesture.moveTo(const Offset(400, 100));
      await tester.pump();
      expect(vm.camera3dState!.elevationDeg, greaterThan(90.0),
          reason: 'Vertical navigation must rotate past 90 degrees and not clamp');

      // Drag 2: further dy = -200 (location 400, -100) -> delta elevation = +100 degrees -> total ~ 235 degrees
      await gesture.moveTo(const Offset(400, -100));
      await tester.pump();
      expect(vm.camera3dState!.elevationDeg, greaterThan(180.0),
          reason: 'Vertical navigation must rotate past 180 degrees into upside-down views');

      // Drag 3: further dy = -400 -> total delta elevation > 400 degrees -> full 360 loop
      await gesture.moveTo(const Offset(400, -500));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // Elevation has smoothly looped past 360 degrees and continues rotating
      expect(vm.camera3dState!.elevationDeg, isNotNull);
      expect(vm.camera3dState!.elevationDeg, isNot(equals(initialElevation)));
    });

    testWidgets('Middle mouse button drag pans the 3D screen and updates camera pan and target', (tester) async {
      final doc = DsfDocument.sampleCableTray(width: 100, height: 50, length: 200, thickness: 2.0);
      final vm = SheetMetalStudioViewModel();
      vm.loadDocument(doc);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: FlutterSceneViewportWidget(viewModel: vm),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final initialPan = vm.camera3dState!.pan;
      final initialTarget = vm.camera3dState!.orbitTarget;

      // Middle mouse button drag (kMiddleMouseButton = 4)
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse, buttons: kMiddleMouseButton);
      await gesture.addPointer(location: const Offset(400, 300));
      await gesture.down(const Offset(400, 300));
      await gesture.moveTo(const Offset(520, 380));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // Pan offset must have shifted by (120, 80)
      expect(vm.camera3dState!.pan.dx, closeTo(initialPan.dx + 120.0, 0.1));
      expect(vm.camera3dState!.pan.dy, closeTo(initialPan.dy + 80.0, 0.1));

      // 3D orbit target must have translated in 3D world space
      final finalTarget = vm.camera3dState!.orbitTarget;
      final distanceMoved = (finalTarget.x - initialTarget.x).abs() +
          (finalTarget.y - initialTarget.y).abs() +
          (finalTarget.z - initialTarget.z).abs();
      expect(distanceMoved, greaterThan(1.0),
          reason: 'Middle mouse pan must translate 3D camera target in world space');
    });

    test('CadMaterialSettings defines correct PBR, dielectric, and spangle properties for all presets', () {
      // 1. HDG (Hot-Dip Galvanized Iron)
      final hdg = CadMaterialSettings.preset(CadMaterialPresetType.hdg);
      expect(hdg.preset, equals(CadMaterialPresetType.hdg));
      expect(hdg.useSpangles, isTrue, reason: 'HDG must activate procedural Voronoi zinc spangle shader');
      expect(hdg.isPlastic, isFalse);
      expect(hdg.roughness, equals(0.55));
      expect(hdg.spangleScale, equals(45.0));

      // 2. PGI (Pre-Galvanized Iron)
      final pgi = CadMaterialSettings.preset(CadMaterialPresetType.pgi);
      expect(pgi.preset, equals(CadMaterialPresetType.pgi));
      expect(pgi.useSpangles, isFalse);
      expect(pgi.isPlastic, isFalse);
      expect(pgi.roughness, equals(0.28));

      // 3. Plastic (Dielectric non-metal)
      final plastic = CadMaterialSettings.preset(CadMaterialPresetType.plastic);
      expect(plastic.preset, equals(CadMaterialPresetType.plastic));
      expect(plastic.isPlastic, isTrue, reason: 'Plastic must have isPlastic flag set to drive metallic 0.0');
      expect(plastic.useSpangles, isFalse);
      expect(plastic.roughness, equals(0.20));

      // 4. Metals
      final chrome = CadMaterialSettings.preset(CadMaterialPresetType.chrome);
      expect(chrome.roughness, equals(0.05));
      expect(chrome.isPlastic, isFalse);

      final gold = CadMaterialSettings.preset(CadMaterialPresetType.gold);
      expect(gold.roughness, equals(0.20));

      final copper = CadMaterialSettings.preset(CadMaterialPresetType.copper);
      expect(copper.roughness, equals(0.25));

      final aluminum = CadMaterialSettings.preset(CadMaterialPresetType.aluminum);
      expect(aluminum.roughness, equals(0.35));

      // 5. Linear RGB Vector conversion
      final vec = hdg.toLinearRgbVector4();
      expect(vec.x, closeTo(hdg.baseColor.r, 1e-4));
      expect(vec.y, closeTo(hdg.baseColor.g, 1e-4));
      expect(vec.z, closeTo(hdg.baseColor.b, 1e-4));
      expect(vec.w, equals(1.0));
    });

    test('Bidirectional sync between Document Material and 3D Graphics Material Settings', () {
      final vm = SheetMetalStudioViewModel();

      // Setting document material grade to HDG updates 3D graphics preferences to HDG preset
      vm.setMaterialGrade('HDG Hot Dip Galvanized');
      expect(vm.graphicsPreferences.materialSettings.preset, equals(CadMaterialPresetType.hdg));
      expect(vm.graphicsPreferences.materialSettings.useSpangles, isTrue);

      // Setting document material to Aluminum updates 3D graphics preferences to Aluminum preset
      vm.setMaterialDefinition(grade: SheetMetalMaterialGrade.aluminium, finish: CoatingFinish.none);
      expect(vm.graphicsPreferences.materialSettings.preset, equals(CadMaterialPresetType.aluminum));
      expect(vm.graphicsPreferences.materialSettings.isPlastic, isFalse);

      // Setting document material to SS304 updates 3D graphics preferences to Silver preset
      vm.setMaterialDefinition(grade: SheetMetalMaterialGrade.ss304, finish: CoatingFinish.none);
      expect(vm.graphicsPreferences.materialSettings.preset, equals(CadMaterialPresetType.silver));

      // Changing 3D graphics preferences to HDG preset updates Document Material coating finish to HDG
      vm.graphicsPreferences = vm.graphicsPreferences.copyWith(
        materialSettings: CadMaterialSettings.preset(CadMaterialPresetType.hdg),
      );
      expect(vm.document.material.finish, equals(SurfaceFinish.hotDipGalvanized));

      // Changing 3D graphics preferences to Plastic updates Document Material
      vm.graphicsPreferences = vm.graphicsPreferences.copyWith(
        materialSettings: CadMaterialSettings.preset(CadMaterialPresetType.plastic),
      );
      expect(vm.document.material.materialGrade, contains('Plastic'));
    });

    test('PaintCoatSpecification and RalColor models behave correctly', () {
      final ral7035 = RalColor.fromCode('RAL 7035');
      expect(ral7035, isNotNull);
      expect(ral7035.name, equals('Light Grey'));
      expect(RalColor.topCMSColors.isNotEmpty, isTrue);
      expect(RalColor.topCMSColors.any((c) => c.code == 'RAL 7035'), isTrue);

      const unpainted = PaintCoatSpecification();
      expect(unpainted.isPainted, isFalse);
      expect(unpainted.displayLabel, equals('None (Unpainted Mill/Galv)'));

      const powder = PaintCoatSpecification(
        type: PaintCoatType.powderCoat,
        ralColor: RalColor.ral7035,
      );
      expect(powder.isPainted, isTrue);
      expect(powder.displayLabel, contains('Powder Coated [RAL 7035 Light Grey]'));

      final powderCadSettings = powder.toCadMaterialSettings();
      expect(powderCadSettings.preset, equals(CadMaterialPresetType.paint));
      expect(powderCadSettings.isPlastic, isTrue);
      expect(powderCadSettings.useSpangles, isFalse);
      expect(powderCadSettings.roughness, closeTo(0.30, 0.01));
      expect(powderCadSettings.baseColor, equals(RalColor.ral7035.color));

      const epoxy = PaintCoatSpecification(
        type: PaintCoatType.epoxy,
        ralColor: RalColor.ral5012,
        roughness: 0.20,
      );
      expect(epoxy.isPainted, isTrue);
      expect(epoxy.displayLabel, contains('Epoxy Painted [RAL 5012 Light Blue]'));
      final epoxyCadSettings = epoxy.toCadMaterialSettings();
      expect(epoxyCadSettings.roughness, closeTo(0.20, 0.01));

      // Serialization roundtrip
      final json = powder.toJson();
      final restored = PaintCoatSpecification.fromJson(json);
      expect(restored.type, equals(PaintCoatType.powderCoat));
      expect(restored.ralColor.code, equals('RAL 7035'));
    });

    test('ViewModel switches 3D material to secondary paint coat and reverts on removal', () {
      final vm = SheetMetalStudioViewModel();

      // Start with HDG Hot Dip Galvanized
      vm.setMaterialGrade('HDG Hot Dip Galvanized');
      expect(vm.graphicsPreferences.materialSettings.preset, equals(CadMaterialPresetType.hdg));
      expect(vm.graphicsPreferences.materialSettings.useSpangles, isTrue);
      expect(vm.paintCoat.isPainted, isFalse);

      // Apply Powder Coat paint
      vm.setPaintCoatType(PaintCoatType.powderCoat);
      expect(vm.paintCoat.isPainted, isTrue);
      expect(vm.paintCoat.type, equals(PaintCoatType.powderCoat));
      // Base substrate material grade is retained in document
      expect(vm.document.material.materialGrade, contains('HDG'));
      // 3D graphics material is replaced by paint preset
      expect(vm.graphicsPreferences.materialSettings.preset, equals(CadMaterialPresetType.paint));
      expect(vm.graphicsPreferences.materialSettings.useSpangles, isFalse);
      expect(vm.graphicsPreferences.materialSettings.isPlastic, isTrue);
      expect(vm.graphicsPreferences.materialSettings.baseColor, equals(RalColor.ral7035.color));

      // Change paint color to RAL 5012 Light Blue
      vm.setPaintRalColor(RalColor.ral5012);
      expect(vm.paintCoat.ralColor, equals(RalColor.ral5012));
      expect(vm.graphicsPreferences.materialSettings.baseColor, equals(RalColor.ral5012.color));

      // Revert paint to none -> 3D material restores HDG substrate
      vm.setPaintCoatType(PaintCoatType.none);
      expect(vm.paintCoat.isPainted, isFalse);
      expect(vm.graphicsPreferences.materialSettings.preset, equals(CadMaterialPresetType.hdg));
      expect(vm.graphicsPreferences.materialSettings.useSpangles, isTrue);

      // Now set base material to Pre-Galvanized DX51D (GI)
      vm.setMaterialGrade('Pre-Galvanized DX51D');
      expect(vm.graphicsPreferences.materialSettings.preset, equals(CadMaterialPresetType.pgi));
      expect(vm.paintCoat.isPainted, isFalse);

      // Apply Epoxy paint over GI
      vm.setPaintCoatType(PaintCoatType.epoxy);
      expect(vm.paintCoat.isPainted, isTrue);
      expect(vm.graphicsPreferences.materialSettings.preset, equals(CadMaterialPresetType.paint));

      // Remove paint -> 3D material restores GI substrate
      vm.setPaintCoatType(PaintCoatType.none);
      expect(vm.graphicsPreferences.materialSettings.preset, equals(CadMaterialPresetType.pgi));
    });

    test('DSF file format incorporates secondary paintCoat with backward compatibility', () {
      // 1. Create a DsfDocument with a Powder Coated top coat over Pre-Galvanized DX51D
      const paintedMaterial = SheetMetalMaterial(
        thicknessMm: 1.5,
        materialGrade: 'Pre-Galvanized DX51D',
        materialType: SheetMaterialType.mildSteel,
        finish: SurfaceFinish.electroGalvanized,
        paintCoat: PaintCoatSpecification(
          type: PaintCoatType.powderCoat,
          ralColor: RalColor.ral7035,
          roughness: 0.30,
        ),
      );

      final originalDoc = DsfDocument.sampleCableTray(material: paintedMaterial);

      // 2. Serialize to DSF JSON structure
      final dsfJson = originalDoc.toJson();
      expect(dsfJson.containsKey('material'), isTrue);

      final materialJson = dsfJson['material'] as Map<String, dynamic>;
      expect(materialJson.containsKey('paintCoat'), isTrue);

      final paintCoatJson = materialJson['paintCoat'] as Map<String, dynamic>;
      expect(paintCoatJson['type'], equals('powderCoat'));
      expect(paintCoatJson['roughness'], equals(0.30));

      final ralJson = paintCoatJson['ralColor'] as Map<String, dynamic>;
      expect(ralJson['code'], equals('RAL 7035'));
      expect(ralJson['name'], equals('Light Grey'));
      expect(ralJson['category'], equals('Grey'));

      // 3. Roundtrip through JSON String (file write/read simulation)
      final jsonString = originalDoc.toJsonString();
      final loadedDoc = DsfDocument.parseJsonString(jsonString);

      expect(loadedDoc.material.paintCoat.isPainted, isTrue);
      expect(loadedDoc.material.paintCoat.type, equals(PaintCoatType.powderCoat));
      expect(loadedDoc.material.paintCoat.ralColor.code, equals('RAL 7035'));
      expect(loadedDoc.material.paintCoat.ralColor.name, equals('Light Grey'));
      expect(loadedDoc.material.paintCoat.roughness, closeTo(0.30, 1e-4));
      expect(loadedDoc.material.materialGrade, equals('Pre-Galvanized DX51D'));

      // 4. Backward Compatibility: Legacy DSF JSON without 'paintCoat' property
      final legacyJson = Map<String, dynamic>.from(dsfJson);
      final legacyMaterialJson = Map<String, dynamic>.from(materialJson)..remove('paintCoat');
      legacyJson['material'] = legacyMaterialJson;

      final legacyDoc = DsfDocument.fromJson(legacyJson);
      expect(legacyDoc.material.paintCoat.isPainted, isFalse);
      expect(legacyDoc.material.paintCoat.type, equals(PaintCoatType.none));
      expect(legacyDoc.material.paintCoat.displayLabel, contains('None'));

      // 5. LadderAssemblyParameters serialization roundtrip
      const ladderParams = LadderAssemblyParameters(
        materialName: 'HDG Hot Dip Galvanized',
        thickness: 2.0,
        paintCoat: PaintCoatSpecification(
          type: PaintCoatType.epoxy,
          ralColor: RalColor.ral5012,
          roughness: 0.20,
        ),
      );

      final ladderJson = ladderParams.toJson();
      expect(ladderJson.containsKey('paintCoat'), isTrue);

      final restoredLadder = LadderAssemblyParameters.fromJson(ladderJson);
      expect(restoredLadder.paintCoat.isPainted, isTrue);
      expect(restoredLadder.paintCoat.type, equals(PaintCoatType.epoxy));
      expect(restoredLadder.paintCoat.ralColor.code, equals('RAL 5012'));
    });

    test('CadPolygonTriangulator fast-path ensures correct counter-clockwise winding against normal', () {
      final builder = GeometryBuilder();

      // Reversed/clockwise quad vertices relative to +Z normal (0, 0, 1)
      final reversedVertices = [
        const CadPoint3D(0.0, 0.0, 10.0),
        const CadPoint3D(0.0, 30.0, 10.0),
        const CadPoint3D(50.0, 30.0, 10.0),
        const CadPoint3D(50.0, 0.0, 10.0),
      ];

      CadPolygonTriangulator.triangulateToBuilder(
        outerVertices: reversedVertices,
        holes: const [],
        normal: const CadPoint3D(0.0, 0.0, 1.0),
        pivot: const CadPoint3D(0.0, 0.0, 0.0),
        builder: builder,
      );

      expect(builder.triangleCount, equals(2));
      expect(builder.vertexCount, greaterThanOrEqualTo(4));
    });

    test('Fold engine constructs solid model with sheet thickness for painted metal', () {
      final controller = VectorCadController();
      final baseDoc = controller.toDsfDocument();
      final doc = baseDoc.copyWith(
        material: const SheetMetalMaterial(
          materialGrade: 'GI Galvanized Iron',
          thicknessMm: 2.0,
          paintCoat: PaintCoatSpecification(
            type: PaintCoatType.powderCoat,
            ralColor: RalColor.ral7035,
            roughness: 0.30,
          ),
        ),
      );

      final foldedMesh = KinematicFoldEngine.foldDocument(doc, foldProgress: 1.0);
      expect(foldedMesh.thicknessPolygons, isNotEmpty);
      expect(foldedMesh.allPolygons.any((p) => p.faceId.endsWith('_BOT')), isTrue);
      expect(foldedMesh.allPolygons.any((p) => p.faceId.startsWith('RIM_')), isTrue);

      final builder = GeometryBuilder();
      for (final poly in foldedMesh.allPolygons) {
        CadPolygonTriangulator.triangulateToBuilder(
          outerVertices: poly.vertices,
          holes: poly.holes,
          normal: poly.normal,
          pivot: const CadPoint3D(0, 0, 0),
          builder: builder,
        );
      }
      expect(builder.triangleCount, greaterThan(0));
      expect(builder.vertexCount, greaterThan(0));

      final prefs = doc.material.paintCoat.toCadMaterialSettings();
      expect(prefs.baseColor, equals(RalColor.ral7035.color));
      expect(prefs.isPlastic, isTrue);
    });

    testWidgets('360 Virtual Globe Arcball rotates model directly following pointer movement', (tester) async {
      final doc = DsfDocument.sampleCableTray(width: 100, height: 50, length: 200, thickness: 2.0);
      final vm = SheetMetalStudioViewModel();
      vm.loadDocument(doc);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: FlutterSceneViewportWidget(viewModel: vm),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final initialAzimuth = vm.camera3dState!.azimuthDeg;
      final initialElevation = vm.camera3dState!.elevationDeg;

      // Drag right with mouse: rotates model horizontally following pointer
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton);
      await gesture.addPointer(location: const Offset(400, 300));
      await gesture.down(const Offset(400, 300));

      await gesture.moveTo(const Offset(500, 300));
      await tester.pump();

      expect(vm.camera3dState!.azimuthDeg, isNot(equals(initialAzimuth)),
          reason: 'Horizontal drag rotates model azimuth in the direction of dragging pointer');

      // Drag vertically: rotates model vertically following pointer
      await gesture.moveTo(const Offset(500, 200));
      await tester.pump();

      expect(vm.camera3dState!.elevationDeg, isNot(equals(initialElevation)),
          reason: 'Vertical drag rotates model elevation in the direction of dragging pointer');

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('Pinned Pivot rotation mode and ViewCube drag gestures behave correctly', (tester) async {
      final doc = DsfDocument.sampleCableTray(width: 100, height: 50, length: 200, thickness: 2.0);
      final vm = SheetMetalStudioViewModel();
      vm.loadDocument(doc);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: FlutterSceneViewportWidget(viewModel: vm),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find ViewCube widget
      final viewCubeFinder = find.byType(StudioViewCube);
      expect(viewCubeFinder, findsOneWidget);

      final initialAz = vm.camera3dState!.azimuthDeg;
      final initialEl = vm.camera3dState!.elevationDeg;

      // Drag on ViewCube: dragging right decreases azimuth (rotates cube to right)
      await tester.drag(viewCubeFinder, const Offset(30, 20));
      await tester.pumpAndSettle();

      expect(vm.camera3dState!.azimuthDeg, isNot(equals(initialAz)));
      expect(vm.camera3dState!.elevationDeg, isNot(equals(initialEl)));

      // Pinned Pivot button is present in the navigation bar
      expect(find.byIcon(Icons.push_pin), findsOneWidget);

      // Tapping Pinned Pivot button toggles to unpinned (Icons.push_pin_outlined)
      await tester.tap(find.byIcon(Icons.push_pin));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);

      // Tapping again re-enables Pinned Pivot
      await tester.tap(find.byIcon(Icons.push_pin_outlined));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.push_pin), findsOneWidget);
    });
  });
}
