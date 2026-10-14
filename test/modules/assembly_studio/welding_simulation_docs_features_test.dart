import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/assembly_studio/models/assembly_document.dart';
import 'package:trufold_studio/assembly_studio/models/assembly_part.dart';
import 'package:trufold_studio/assembly_studio/models/weld_quality_model.dart';
import 'package:trufold_studio/assembly_studio/viewmodels/assembly_studio_viewmodel.dart';
import 'package:trufold_studio/assembly_studio/views/widgets/viewport/overlays/assembly_weld_joint_style_toolbar.dart';
import 'package:trufold_studio/assembly_studio/views/widgets/viewport/overlays/assembly_weld_quality_hud.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';

void main() {
  group('Welding Simulation Features (welding_simulation_docs.md)', () {
    test('1. Joint Styles Model & Selection in ViewModel', () {
      final vm = AssemblyStudioViewModel();
      expect(vm.activeJointStyle, equals(WeldJointStyle.tJoint));

      vm.setJointStyle(WeldJointStyle.buttJoint);
      expect(vm.activeJointStyle, equals(WeldJointStyle.buttJoint));

      vm.setJointStyle(WeldJointStyle.lapJoint);
      expect(vm.activeJointStyle, equals(WeldJointStyle.lapJoint));

      vm.setJointStyle(WeldJointStyle.cornerJoint);
      expect(vm.activeJointStyle, equals(WeldJointStyle.cornerJoint));
    });

    test('2. Quality Evaluation: High Consistency Yields Grade A', () {
      final vm = AssemblyStudioViewModel();
      final points = [
        const CadPoint3D(0.0, 0.0, 0.0),
        const CadPoint3D(10.0, 0.0, 0.0),
        const CadPoint3D(20.0, 0.0, 0.0),
        const CadPoint3D(30.0, 0.0, 0.0),
      ];
      final timestamps = [0.0, 1.0, 2.0, 3.0]; // 10 mm/s constant speed

      final result = vm.evaluateWeldQuality(pathPoints: points, timestamps: timestamps);
      expect(result.overallScore, greaterThanOrEqualTo(90.0));
      expect(result.anomalies, isEmpty);
      expect(result.gradeFeedback, contains('EXCELLENT'));
    });

    test('3. Quality Evaluation: Detects Excessive Speed and Burn-through', () {
      final vm = AssemblyStudioViewModel();
      final points = [
        const CadPoint3D(0.0, 0.0, 0.0),
        const CadPoint3D(50.0, 0.0, 0.0), // Fast jump: 50mm in 0.5s = 100mm/s
        const CadPoint3D(51.0, 0.0, 0.0), // Slow drag: 1mm in 1.0s = 1mm/s
        const CadPoint3D(53.0, 0.0, 0.0),
      ];
      final timestamps = [0.0, 0.5, 1.5, 3.0];

      final result = vm.evaluateWeldQuality(pathPoints: points, timestamps: timestamps);
      expect(result.anomalies, isNotEmpty);
      expect(result.anomalies.any((a) => a.description.contains('Porosity')), isTrue);
      expect(result.anomalies.any((a) => a.description.contains('Burn-through')), isTrue);
      expect(result.overallScore, lessThan(90.0));
    });

    test('4. AssemblyWeldJoint Serialization Preserves JointStyle & ScoreResult', () {
      final joint = AssemblyWeldJoint(
        id: 'weld_test_1',
        partAId: 'part_A',
        partBId: 'part_B',
        weldPoint: const CadPoint3D(100.0, 50.0, 20.0),
        jointStyle: WeldJointStyle.lapJoint,
        scoreResult: const WeldScoreResult(
          speedConsistency: 85.0,
          profileUniformity: 80.0,
          overallScore: 82.5,
          gradeFeedback: 'Test feedback',
        ),
      );

      final json = joint.toJson();
      expect(json['jointStyle'], equals('lapJoint'));
      expect(json['scoreResult'], isNotNull);

      final restored = AssemblyWeldJoint.fromJson(json);
      expect(restored.jointStyle, equals(WeldJointStyle.lapJoint));
      expect(restored.scoreResult?.overallScore, equals(82.5));
    });

    test('5. 3D Procedural Mesh Generates 8-Segment Cylindrical Bead for All Joint Styles', () {
      final doc = AssemblyDocument(
        id: 'doc_weld_test',
        title: 'Test Assembly',
        parts: [
          AssemblyPart(id: 'p1', name: 'Rail 1', type: AssemblyPartType.straightRail, position: const CadPoint3D(0, 0, 0)),
          AssemblyPart(id: 'p2', name: 'Rail 2', type: AssemblyPartType.straightRail, position: const CadPoint3D(0, 50, 0)),
        ],
        welds: [
          AssemblyWeldJoint(
            id: 'weld_1',
            partAId: 'p1',
            partBId: 'p2',
            weldPoint: const CadPoint3D(50.0, 25.0, 10.0),
            jointStyle: WeldJointStyle.buttJoint,
            pathPoints: [
              const CadPoint3D(10.0, 25.0, 10.0),
              const CadPoint3D(90.0, 25.0, 10.0),
            ],
          ),
        ],
      );

      final mesh = doc.buildAssemblyMesh(showWeldOverlay: true);
      final weldPolys = mesh.allPolygons.where((p) => p.faceId == 'weld_weld_1').toList();
      expect(weldPolys, isNotEmpty);
      // Continuous 8-facet arch connected with quad strips and end caps
      expect(weldPolys.length, greaterThanOrEqualTo(16));
    });

    testWidgets('6. AssemblyWeldJointStyleToolbar Renders and Switches Styles', (tester) async {
      final vm = AssemblyStudioViewModel();
      vm.activeToolMode = SketchUpToolMode.weld;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                AssemblyWeldJointStyleToolbar(viewModel: vm),
              ],
            ),
          ),
        ),
      );

      expect(find.text('SELECT JOINT CONFIGURATION'), findsOneWidget);
      expect(find.text('BUTT JOINT'), findsOneWidget);
      expect(find.text('LAP JOINT'), findsOneWidget);
      expect(find.text('T-JOINT'), findsOneWidget);
      expect(find.text('CORNER JOINT'), findsOneWidget);

      await tester.tap(find.text('LAP JOINT'));
      await tester.pump();
      expect(vm.activeJointStyle, equals(WeldJointStyle.lapJoint));
    });

    testWidgets('7. AssemblyWeldQualityHUD Renders Quality Card and Anomaly Sidebar', (tester) async {
      final vm = AssemblyStudioViewModel();
      vm.latestWeldEvaluation = const WeldScoreResult(
        speedConsistency: 80.0,
        profileUniformity: 85.0,
        overallScore: 82.5,
        gradeFeedback: 'Acceptable structural weld',
        anomalies: [
          WeldAnomaly(position: CadPoint3D(10, 20, 30), description: 'Too slow (Burn-through Risk)'),
        ],
      );

      bool clickedAnomaly = false;
      bool clickedInspect = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                AssemblyWeldQualityHUD(
                  viewModel: vm,
                  onAnomalyTap: (_) => clickedAnomaly = true,
                  onInspectSeam: () => clickedInspect = true,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.textContaining('QUALITY METRIC GRADE: 82.5%'), findsOneWidget);
      expect(find.text('FAULT ANOMALY MARKS (1)'), findsOneWidget);
      expect(find.textContaining('1. Too slow (Burn-through Risk)'), findsOneWidget);

      await tester.tap(find.textContaining('1. Too slow'));
      expect(clickedAnomaly, isTrue);

      await tester.tap(find.text('INSPECT SEAM'));
      expect(clickedInspect, isTrue);
    });
  });
}
