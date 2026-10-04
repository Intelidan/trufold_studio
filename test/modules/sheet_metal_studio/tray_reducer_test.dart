import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cnc_punch_primitive.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_3d_opening_detector.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_opening_plane_analyzer.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/tray_reducer_scaler.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cms/cms_scaling_controller.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_product_contract.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cms/cms_physical_port.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';

void main() {
  late DsfDocument baselineDoc;
  late DsfDocument trunkingDoc;

  setUp(() {
    final trayFile = File('assets/dsf_templates/tray_accessories/reducer_100x50x50.dsf');
    baselineDoc = DsfDocument.fromJson(jsonDecode(trayFile.readAsStringSync()) as Map<String, dynamic>);

    final trunkingFile = File('assets/dsf_templates/trunking_accessories/reducer_100x100x50x50.dsf');
    trunkingDoc = DsfDocument.fromJson(jsonDecode(trunkingFile.readAsStringSync()) as Map<String, dynamic>);
  });

  group('Cable Tray Reducer - Dedicated Parametric Engine & Scaling', () {
    test('TC-01: Template Classification & Baseline Geometry (SS1 & SS2)', () {
      expect(TrayReducerScaler.isTrayReducer(baselineDoc), isTrue);
      expect(TrayReducerScaler.isTrayReducer(trunkingDoc), isFalse);

      final fold = KinematicFoldEngine.foldDocument(baselineDoc, foldProgress: 1.0);
      final openings = Cms3DOpeningDetector.detectOpenings(document: baselineDoc, foldResult: fold);

      // Reducer MUST have strictly 2 ports (never 6 phantom ports)
      expect(openings.length, equals(2));

      // Analyze physical measured openings
      final measured = openings.map((o) => CmsOpeningPlaneAnalyzer.analyze(raw: o, document: baselineDoc, foldResult: fold)).toList();
      final port1 = measured.firstWhere((m) => m.normal.y < -0.9);
      expect(port1.width, closeTo(100.0, 1.5));
      expect(port1.height, closeTo(50.0, 1.5));
      expect(port1.floorP1.z, closeTo(0.0, 1e-3));
      expect(port1.floorP2.z, closeTo(0.0, 1e-3));

      // Port 2: Outlet (50mm width, 50mm height, normal (0, 1, 0))
      final port2 = measured.firstWhere((m) => m.normal.y > 0.9);
      expect(port2.width, closeTo(50.0, 1.5));
      expect(port2.height, closeTo(50.0, 1.5));
      expect(port2.floorP1.z, closeTo(0.0, 1e-3));
      expect(port2.floorP2.z, closeTo(0.0, 1e-3));

      // Port borders pass through the outer coupler holes (within body, ~20-25mm from mouth)
      expect(port1.floorP1.y, closeTo(20.0, 5.0));
      expect(port2.floorP1.y, closeTo(230.0, 5.0));
    });

    test('TC-02: Concentric (Straight) Reducer Scaling', () {
      final scaled = TrayReducerScaler.scaleWithParameters(
        baselineDoc,
        const TrayReducerScaleParameters(
          port1Width: 150.0,
          port1Height: 50.0,
          port2Width: 100.0,
          port2Height: 50.0,
          length: 250.0,
          alignment: ReducerAlignment.straight,
        ),
      );

      expect(scaled.faces.length, equals(5));
      expect(scaled.bends.length, equals(4));

      final fold = KinematicFoldEngine.foldDocument(scaled, foldProgress: 1.0);
      final openings = Cms3DOpeningDetector.detectOpenings(document: scaled, foldResult: fold);
      expect(openings.length, equals(2));

      final measured = openings.map((o) => CmsOpeningPlaneAnalyzer.analyze(raw: o, document: scaled, foldResult: fold)).toList();
      final p1 = measured.firstWhere((m) => m.normal.y < -0.9);
      final p2 = measured.firstWhere((m) => m.normal.y > 0.9);

      expect(p1.width, closeTo(150.0, 1.5));
      expect(p2.width, closeTo(100.0, 1.5));
      expect(p1.height, closeTo(50.0, 1.5));
      expect(p2.height, closeTo(50.0, 1.5));
    });

    test('TC-03: Left Reducer Alignment (Left Wall Straight at 0°)', () {
      final scaled = TrayReducerScaler.scaleWithParameters(
        baselineDoc,
        const TrayReducerScaleParameters(
          port1Width: 100.0,
          port1Height: 50.0,
          port2Width: 50.0,
          port2Height: 50.0,
          length: 250.0,
          alignment: ReducerAlignment.left,
        ),
      );

      final fold = KinematicFoldEngine.foldDocument(scaled, foldProgress: 1.0);
      final openings = Cms3DOpeningDetector.detectOpenings(document: scaled, foldResult: fold);
      expect(openings.length, equals(2));

      // Left cheek bend B1 must be strictly vertical (dx == 0, straight at 0°)
      final b1 = scaled.bends.firstWhere((b) => b.id == 'B1');
      expect((b1.p1.x - b1.p2.x).abs(), lessThan(1e-4));

      // Right cheek bend B2 must taper inward
      final b2 = scaled.bends.firstWhere((b) => b.id == 'B2');
      expect((b2.p1.x - b2.p2.x).abs(), closeTo(50.0, 1e-4));
    });

    test('TC-04: Right Reducer Alignment (Right Wall Straight at 0°)', () {
      final scaled = TrayReducerScaler.scaleWithParameters(
        baselineDoc,
        const TrayReducerScaleParameters(
          port1Width: 100.0,
          port1Height: 50.0,
          port2Width: 50.0,
          port2Height: 50.0,
          length: 250.0,
          alignment: ReducerAlignment.right,
        ),
      );

      final fold = KinematicFoldEngine.foldDocument(scaled, foldProgress: 1.0);
      final openings = Cms3DOpeningDetector.detectOpenings(document: scaled, foldResult: fold);
      expect(openings.length, equals(2));

      // Right cheek bend B2 must be strictly vertical (dx == 0, straight at 0°)
      final b2 = scaled.bends.firstWhere((b) => b.id == 'B2');
      expect((b2.p1.x - b2.p2.x).abs(), lessThan(1e-4));

      // Left cheek bend B1 must taper inward
      final b1 = scaled.bends.firstWhere((b) => b.id == 'B1');
      expect((b1.p1.x - b1.p2.x).abs(), closeTo(50.0, 1e-4));
    });

    test('TC-05: Height Scaling & Universal 95mm Coupler Rule', () {
      // Scale H to 100mm (>= 95mm)
      final scaled100 = TrayReducerScaler.scaleWithParameters(
        baselineDoc,
        const TrayReducerScaleParameters(
          port1Width: 100.0,
          port1Height: 100.0,
          port2Width: 50.0,
          port2Height: 100.0,
          length: 250.0,
          alignment: ReducerAlignment.straight,
        ),
      );

      // Cheek coupler slots should have 2 slots per column at 50mm pitch
      final cheekPunches = scaled100.punches.where((p) => p.role == CncPunchRole.coupler).toList();
      // 4 cheeks/ends * 2 columns * 2 slots = 16 coupler slots
      expect(cheekPunches.length, equals(16));
    });

    test('TC-06: Coupler Flaps Generation & Fold Bends', () {
      final scaledWithFlaps = TrayReducerScaler.scaleWithParameters(
        baselineDoc,
        const TrayReducerScaleParameters(
          port1Width: 100.0,
          port1Height: 50.0,
          port2Width: 50.0,
          port2Height: 50.0,
          includeCouplerFlaps: true,
          couplerFlapLength: 90.0,
        ),
      );

      // 5 baseline faces + 4 flaps = 9 faces
      expect(scaledWithFlaps.faces.length, equals(9));
      expect(scaledWithFlaps.faces.any((f) => f.id == 'F_FLAP_4_P1'), isTrue);
      expect(scaledWithFlaps.faces.any((f) => f.id == 'F_FLAP_4_P2'), isTrue);
      expect(scaledWithFlaps.faces.any((f) => f.id == 'F_FLAP_1_P1'), isTrue);
      expect(scaledWithFlaps.faces.any((f) => f.id == 'F_FLAP_1_P2'), isTrue);

      // 4 baseline bends + 4 flap bends = 8 bends
      expect(scaledWithFlaps.bends.length, equals(8));
      expect(scaledWithFlaps.bends.any((b) => b.id == 'BF_4_P1'), isTrue);
      expect(scaledWithFlaps.bends.any((b) => b.id == 'BF_1_P1'), isTrue);
    });

    test('TC-06b: Flap 3D normals strictly parallel to duct run across all alignments', () {
      for (final align in [ReducerAlignment.straight, ReducerAlignment.left, ReducerAlignment.right]) {
        final scaled = TrayReducerScaler.scaleWithParameters(
          baselineDoc,
          TrayReducerScaleParameters(
            port1Width: 200.0,
            port2Width: 100.0,
            port1Height: 100.0,
            port2Height: 50.0,
            length: 150.0,
            alignment: align,
            includeCouplerFlaps: false,
          ),
        );
        final fold = KinematicFoldEngine.foldDocument(scaled, foldProgress: 1.0);
        for (final p in fold.polygons) {
          if (p.faceId == 'F_FLAP_4_P1' || p.faceId == 'F_FLAP_4_P2') {
            // Left flaps must point in +X direction (1.0, 0.0, 0.0)
            expect(p.normal.x, closeTo(1.0, 1e-3));
            expect(p.normal.y, closeTo(0.0, 1e-3));
            expect(p.normal.z, closeTo(0.0, 1e-3));
          } else if (p.faceId == 'F_FLAP_1_P1' || p.faceId == 'F_FLAP_1_P2') {
            // Right flaps must point in -X direction (-1.0, 0.0, 0.0)
            expect(p.normal.x, closeTo(-1.0, 1e-3));
            expect(p.normal.y, closeTo(0.0, 1e-3));
            expect(p.normal.z, closeTo(0.0, 1e-3));
          }
        }
      }
    });

    test('TC-07: Full Scaling Controller Integration (No Drawing Dismantle)', () {
      final basePorts = [
        const CmsPhysicalPort(id: 'PORT_1', index: 1, width: 100.0, height: 50.0, normal: CadPoint3D(0.0, -1.0, 0.0)),
        const CmsPhysicalPort(id: 'PORT_2', index: 2, width: 50.0, height: 50.0, normal: CadPoint3D(0.0, 1.0, 0.0)),
      ];

      final controller = CmsScalingController(
        baselineDocument: baselineDoc,
        contract: CmsProductContract.straightReducer,
        baselinePorts: basePorts,
      );

      // Verify controller starts in reducer mode with 2 ports
      expect(controller.effectiveScalingProfile, equals(CmsScalingProfile.reducer));
      expect(controller.isTrayReducer, isTrue);
      expect(controller.model.parameters.containsKey('port1_width'), isTrue);
      expect(controller.model.parameters.containsKey('port2_width'), isTrue);
      expect(controller.model.parameters.containsKey('port3_width'), isFalse);

      // Parameter change: Port 1 width to 150mm
      controller.selectParameter('port1_width');
      controller.evaluateMorph(150.0);
      final preview = controller.currentPreview;
      expect(preview, isNotNull);
      expect(preview!.isValid, isTrue);

      // Check preview document maintains exactly 5 faces and 4 bends (NOT dismantled!)
      expect(preview.scaledDocument.faces.length, equals(5));
      expect(preview.scaledDocument.bends.length, equals(4));

      // Exactly 2 ports derived
      expect(preview.derivedPorts.length, equals(2));

      // Alignment switch to Left Reducer
      controller.setReducerAlignment(ReducerAlignment.left);
      expect(controller.reducerAlignment, equals(ReducerAlignment.left));

      final leftPreview = controller.currentPreview;
      expect(leftPreview, isNotNull);
      expect(leftPreview!.isValid, isTrue);
      final b1Left = leftPreview.scaledDocument.bends.firstWhere((b) => b.id == 'B1');
      expect((b1Left.p1.x - b1Left.p2.x).abs(), lessThan(1e-4));
    });

    test('TC-08: DSF Format Serialization & Persistence Roundtrip', () {
      // 1. Verify baseline DSF contains reducer parameters
      expect(baselineDoc.parameters.containsKey('reducer_alignment'), isTrue);
      expect(baselineDoc.parameters['reducer_alignment'], equals(0.0));

      // 2. Scale to Left Reducer and verify parameters and metadata
      final scaledLeft = TrayReducerScaler.scaleWithParameters(
        baselineDoc,
        const TrayReducerScaleParameters(
          port1Width: 150.0,
          port2Width: 75.0,
          port1Height: 75.0,
          port2Height: 50.0,
          length: 200.0,
          alignment: ReducerAlignment.left,
        ),
      );

      expect(scaledLeft.parameters['reducer_alignment'], equals(1.0));
      expect(scaledLeft.parameters['length'], equals(200.0));
      expect(scaledLeft.parameters['port1_width'], equals(150.0));
      expect(scaledLeft.parameters['port2_width'], equals(75.0));
      expect(scaledLeft.metadata['reducer_alignment'], equals('left'));
      expect(scaledLeft.metadata['variantName'], equals('Left Reducer'));
      expect(scaledLeft.metadata['fittingMetadata']['parameters']['reducer_alignment'], equals('left'));

      // 3. Serialize to DSF JSON and deserialize back
      final dsfJson = scaledLeft.toJson();
      final restoredDoc = DsfDocument.fromJson(dsfJson);

      expect(restoredDoc.parameters['reducer_alignment'], equals(1.0));
      expect(restoredDoc.parameters['length'], equals(200.0));
      expect(restoredDoc.metadata['reducer_alignment'], equals('left'));
      expect(restoredDoc.metadata['variantName'], equals('Left Reducer'));

      // 4. Verify CmsScalingController initialized from restored DSF automatically picks up alignment
      final basePorts = [
        const CmsPhysicalPort(id: 'PORT_1', index: 1, width: 150.0, height: 75.0, normal: CadPoint3D(0.0, -1.0, 0.0)),
        const CmsPhysicalPort(id: 'PORT_2', index: 2, width: 75.0, height: 50.0, normal: CadPoint3D(0.0, 1.0, 0.0)),
      ];
      final controller = CmsScalingController(
        contract: CmsProductContract.straightReducer,
        baselineDocument: restoredDoc,
        baselinePorts: basePorts,
      );
      expect(controller.reducerAlignment, equals(ReducerAlignment.left));
      expect(controller.effectiveScalingProfile, equals(CmsScalingProfile.reducer));
    });

    test('TC-09: Flange Corners Stay Straight & In Line with Product Edge (Both Inside & Outside Directions)', () {
      for (final align in [ReducerAlignment.straight, ReducerAlignment.left, ReducerAlignment.right]) {
        for (final isOutside in [false, true]) {
          final scaled = TrayReducerScaler.scaleWithParameters(
            baselineDoc,
            TrayReducerScaleParameters(
              port1Width: 200.0,
              port2Width: 100.0,
              port1Height: 100.0,
              port2Height: 50.0,
              length: 150.0,
              alignment: align,
              includeCouplerFlaps: false,
              isOutsideFlange: isOutside,
            ),
          );

          // 1. Verify 2D outer contour includes all face transitions without shortcuts
          expect(scaled.outerContour.length, equals(13)); // 12 unique points + closed start point
          final contourIds = [
            scaled.faces.firstWhere((f) => f.id == 'F_2').vertices[2], // p1Left
            scaled.faces.firstWhere((f) => f.id == 'F_2').vertices[3], // p1Right
            scaled.faces.firstWhere((f) => f.id == 'F_1').vertices[3], // fl2P1
            scaled.faces.firstWhere((f) => f.id == 'F_0').vertices[1], // vRight1
            scaled.faces.firstWhere((f) => f.id == 'F_0').vertices[2], // vRight2
            scaled.faces.firstWhere((f) => f.id == 'F_1').vertices[0], // fl2P2
            scaled.faces.firstWhere((f) => f.id == 'F_2').vertices[0], // p2Right
            scaled.faces.firstWhere((f) => f.id == 'F_2').vertices[1], // p2Left
            scaled.faces.firstWhere((f) => f.id == 'F_4').vertices[3], // fl1P1
            scaled.faces.firstWhere((f) => f.id == 'F_3').vertices[1], // vLeft1
            scaled.faces.firstWhere((f) => f.id == 'F_3').vertices[2], // vLeft2
            scaled.faces.firstWhere((f) => f.id == 'F_4').vertices[0], // fl1P2
            scaled.faces.firstWhere((f) => f.id == 'F_2').vertices[2], // p1Left
          ];
          for (int i = 0; i < contourIds.length; i++) {
            expect(scaled.outerContour[i].x, closeTo(contourIds[i].x, 1e-4));
            expect(scaled.outerContour[i].y, closeTo(contourIds[i].y, 1e-4));
          }

          // 2. Verify 3D folded geometry: flange ends are strictly in line with port mouths
          final fold = KinematicFoldEngine.foldDocument(scaled, foldProgress: 1.0);
          final f0Poly = fold.polygons.firstWhere((p) => p.faceId == 'F_0');
          final f3Poly = fold.polygons.firstWhere((p) => p.faceId == 'F_3');

          // F_0 (Right flange): vertices=[fl2P1, vRight1, vRight2, fl2P2]
          // Port 1 mouth (y=0 in 3D): fl2P1 and vRight1 must have matching Y (difference < 1e-3)
          final vrFl2P1 = f0Poly.vertices[0];
          final vrVRight1 = f0Poly.vertices[1];
          final vrVRight2 = f0Poly.vertices[2];
          final vrFl2P2 = f0Poly.vertices[3];

          expect((vrFl2P1.y - vrVRight1.y).abs(), lessThan(1e-3),
              reason: '$align Right flange Port 1 end not straight (isOutside=$isOutside): fl2P1.y=${vrFl2P1.y}, vRight1.y=${vrVRight1.y}');
          expect((vrFl2P2.y - vrVRight2.y).abs(), lessThan(1e-3),
              reason: '$align Right flange Port 2 end not straight (isOutside=$isOutside): fl2P2.y=${vrFl2P2.y}, vRight2.y=${vrVRight2.y}');

          // F_3 (Left flange): vertices=[fl1P1, vLeft1, vLeft2, fl1P2]
          // Port 1 mouth (y=0 in 3D): fl1P2 and vLeft2 must have matching Y
          // Port 2 mouth (y=150 in 3D): fl1P1 and vLeft1 must have matching Y
          final vlFl1P1 = f3Poly.vertices[0];
          final vlVLeft1 = f3Poly.vertices[1];
          final vlVLeft2 = f3Poly.vertices[2];
          final vlFl1P2 = f3Poly.vertices[3];

          expect((vlFl1P2.y - vlVLeft2.y).abs(), lessThan(1e-3),
              reason: '$align Left flange Port 1 end not straight (isOutside=$isOutside): fl1P2.y=${vlFl1P2.y}, vLeft2.y=${vlVLeft2.y}');
          expect((vlFl1P1.y - vlVLeft1.y).abs(), lessThan(1e-3),
              reason: '$align Left flange Port 2 end not straight (isOutside=$isOutside): fl1P1.y=${vlFl1P1.y}, vLeft1.y=${vlVLeft1.y}');
        }
      }
    });

    test('TC-10: Flange Angle 135° Preservation and Reversible Toggling (135° <-> 90°)', () {
      // 1. Verify baseline document has 135° flange bends
      final fl1Base = baselineDoc.bends.firstWhere((b) => b.id == 'FL1');
      final fl2Base = baselineDoc.bends.firstWhere((b) => b.id == 'FL2');
      expect(fl1Base.targetAngleDeg, equals(135.0));
      expect(fl2Base.targetAngleDeg, equals(135.0));

      // 2. Scale without explicit flange angle: verify 135° is preserved (NOT converted to 90°)
      final scaledDefault = TrayReducerScaler.scaleWithParameters(
        baselineDoc,
        const TrayReducerScaleParameters(
          port1Width: 150.0,
          port2Width: 100.0,
          port1Height: 50.0,
          port2Height: 50.0,
          length: 200.0,
        ),
      );

      final fl1Default = scaledDefault.bends.firstWhere((b) => b.id == 'FL1');
      final fl2Default = scaledDefault.bends.firstWhere((b) => b.id == 'FL2');
      expect(fl1Default.targetAngleDeg, equals(135.0), reason: 'Default scaling must preserve baseline 135° flange angle');
      expect(fl2Default.targetAngleDeg, equals(135.0), reason: 'Default scaling must preserve baseline 135° flange angle');
      expect(scaledDefault.parameters['flange_angle'], equals(135.0));

      // 3. User switches to 90° flange
      final scaled90 = TrayReducerScaler.scaleWithParameters(
        baselineDoc,
        const TrayReducerScaleParameters(
          port1Width: 150.0,
          port2Width: 100.0,
          port1Height: 50.0,
          port2Height: 50.0,
          length: 200.0,
          flangeAngle: 90.0,
        ),
      );

      final fl1_90 = scaled90.bends.firstWhere((b) => b.id == 'FL1');
      final fl2_90 = scaled90.bends.firstWhere((b) => b.id == 'FL2');
      expect(fl1_90.targetAngleDeg, equals(90.0));
      expect(fl2_90.targetAngleDeg, equals(90.0));
      expect(scaled90.parameters['flange_angle'], equals(90.0));

      // 4. User switches back to 135° flange
      final scaled135 = TrayReducerScaler.scaleWithParameters(
        scaled90,
        const TrayReducerScaleParameters(
          port1Width: 150.0,
          port2Width: 100.0,
          port1Height: 50.0,
          port2Height: 50.0,
          length: 200.0,
          flangeAngle: 135.0,
        ),
      );

      final fl1_135 = scaled135.bends.firstWhere((b) => b.id == 'FL1');
      final fl2_135 = scaled135.bends.firstWhere((b) => b.id == 'FL2');
      expect(fl1_135.targetAngleDeg, equals(135.0));
      expect(fl2_135.targetAngleDeg, equals(135.0));
      expect(scaled135.parameters['flange_angle'], equals(135.0));

      // 5. Verify 3D alignment holds for both 90° and 135°
      for (final doc in [scaled90, scaled135]) {
        final fold = KinematicFoldEngine.foldDocument(doc, foldProgress: 1.0);
        final f0 = fold.polygons.firstWhere((p) => p.faceId == 'F_0');
        final f3 = fold.polygons.firstWhere((p) => p.faceId == 'F_3');

        // Right flange Port 1 and Port 2 ends straight
        expect((f0.vertices[0].y - f0.vertices[1].y).abs(), lessThan(1e-3));
        expect((f0.vertices[3].y - f0.vertices[2].y).abs(), lessThan(1e-3));
        // Left flange Port 1 and Port 2 ends straight
        expect((f3.vertices[3].y - f3.vertices[2].y).abs(), lessThan(1e-3));
        expect((f3.vertices[0].y - f3.vertices[1].y).abs(), lessThan(1e-3));
      }
    });

    test('TC-11: ViewModel Live Bend Angle Update & Two-Way Sync with Scaling Controller', () {
      final vm = SheetMetalStudioViewModel(initialDocument: baselineDoc);
      vm.startTeachScaling();

      // Initial state: flange angle is 135°
      final initialFl1 = vm.document.bends.firstWhere((b) => b.id == 'FL1');
      expect(initialFl1.targetAngleDeg, equals(135.0));

      // User changes FL1 to 90° in BendPropertySheet
      vm.updateBend(initialFl1.copyWith(targetAngleDeg: 90.0));
      expect(vm.document.bends.firstWhere((b) => b.id == 'FL1').targetAngleDeg, equals(90.0));
      expect(vm.document.bends.firstWhere((b) => b.id == 'FL2').targetAngleDeg, equals(90.0));

      // User changes FL1 back to 135° in BendPropertySheet
      final bend90 = vm.document.bends.firstWhere((b) => b.id == 'FL1');
      vm.updateBend(bend90.copyWith(targetAngleDeg: 135.0));
      expect(vm.document.bends.firstWhere((b) => b.id == 'FL1').targetAngleDeg, equals(135.0));
      expect(vm.document.bends.firstWhere((b) => b.id == 'FL2').targetAngleDeg, equals(135.0));

      // Also verify applyCmsMorphParameter('flange_angle', 90.0)
      vm.applyCmsMorphParameter('flange_angle', 90.0);
      expect(vm.document.bends.firstWhere((b) => b.id == 'FL1').targetAngleDeg, equals(90.0));
      expect(vm.document.bends.firstWhere((b) => b.id == 'FL2').targetAngleDeg, equals(90.0));

      // And applyCmsMorphParameter('flange_angle', 135.0)
      vm.applyCmsMorphParameter('flange_angle', 135.0);
      expect(vm.document.bends.firstWhere((b) => b.id == 'FL1').targetAngleDeg, equals(135.0));
      expect(vm.document.bends.firstWhere((b) => b.id == 'FL2').targetAngleDeg, equals(135.0));
    });
  });
}
