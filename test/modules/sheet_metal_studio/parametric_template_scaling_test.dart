import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/constraints/geometric_constraint_solver.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/topological_zone_morpher.dart';

void main() {
  group('Parametric Template Scaling & 3-Point Validation (Sets 4 & 5)', () {
    test('1. 90° Flat Bend (cableTrayBend90) 3-Point Validation (Nominal, Min, Max)', () {
      final baselineBend = TopologicalZoneMorpher.createBaselineBend90(
        width: 100.0,
        height: 50.0,
        radius: 100.0,
      );

      final originalPunches = baselineBend.punches;
      expect(originalPunches.isNotEmpty, isTrue);

      // --- Point 1: Nominal (W=300, H=50, R=100) ---
      final resNominal = GeometricConstraintSolver.solve(
        document: baselineBend,
        parameterOverrides: {
          'width': 300.0,
          'height': 50.0,
          'radius': 100.0,
        },
      );
      expect(resNominal.success, isTrue);
      final docNominal = resNominal.updatedDocument;
      expect(docNominal.parameters['width'], closeTo(300.0, 1e-2));
      expect(docNominal.parameters['height'], closeTo(50.0, 1e-2));
      // Verify punch dimensions are preserved
      for (final p in docNominal.punches) {
        expect(p.widthMm, anyOf(closeTo(30.0, 1e-2), closeTo(7.0, 1e-2)));
        expect(p.lengthMm, anyOf(closeTo(30.0, 1e-2), closeTo(7.0, 1e-2)));
      }
      expect(docNominal.outerContour.length, greaterThanOrEqualTo(8));

      // --- Point 2: Minimum (W=100, H=25, R=50) ---
      final resMin = GeometricConstraintSolver.solve(
        document: baselineBend,
        parameterOverrides: {
          'width': 100.0,
          'height': 25.0,
          'radius': 50.0,
        },
      );
      expect(resMin.success, isTrue);
      final docMin = resMin.updatedDocument;
      expect(docMin.parameters['width'], closeTo(100.0, 1e-2));
      expect(docMin.parameters['height'], closeTo(25.0, 1e-2));
      for (final p in docMin.punches) {
        expect(p.widthMm, anyOf(closeTo(30.0, 1e-2), closeTo(7.0, 1e-2)));
        expect(p.lengthMm, anyOf(closeTo(30.0, 1e-2), closeTo(7.0, 1e-2)));
      }

      // --- Point 3: Maximum (W=600, H=100, R=300) ---
      final resMax = GeometricConstraintSolver.solve(
        document: baselineBend,
        parameterOverrides: {
          'width': 600.0,
          'height': 100.0,
          'radius': 300.0,
        },
      );
      expect(resMax.success, isTrue);
      final docMax = resMax.updatedDocument;
      expect(docMax.parameters['width'], closeTo(600.0, 1e-2));
      expect(docMax.parameters['height'], closeTo(100.0, 1e-2));
      for (final p in docMax.punches) {
        expect(p.widthMm, anyOf(closeTo(30.0, 1e-2), closeTo(7.0, 1e-2)));
        expect(p.lengthMm, anyOf(closeTo(30.0, 1e-2), closeTo(7.0, 1e-2)));
      }
    });

    test('2. Straight Cable Tray (cableTrayStraight) 3-Point Validation (Nominal, Min, Max)', () {
      final baselineStraight = TopologicalZoneMorpher.createBaselineStraight(
        width: 100.0,
        height: 50.0,
        length: 1000.0,
      );

      // --- Point 1: Nominal (W=300, H=50, L=1500) ---
      final resNominal = GeometricConstraintSolver.solve(
        document: baselineStraight,
        parameterOverrides: {
          'width': 300.0,
          'height': 50.0,
          'length': 1500.0,
        },
      );
      expect(resNominal.success, isTrue);
      final docNominal = resNominal.updatedDocument;
      expect(docNominal.parameters['width'], closeTo(300.0, 1e-2));
      expect(docNominal.parameters['length'], closeTo(1500.0, 1e-2));

      // --- Point 2: Minimum (W=100, H=25, L=500) ---
      final resMin = GeometricConstraintSolver.solve(
        document: baselineStraight,
        parameterOverrides: {
          'width': 100.0,
          'height': 25.0,
          'length': 500.0,
        },
      );
      expect(resMin.success, isTrue);
      final docMin = resMin.updatedDocument;
      expect(docMin.parameters['width'], closeTo(100.0, 1e-2));
      expect(docMin.parameters['length'], closeTo(500.0, 1e-2));

      // --- Point 3: Maximum (W=600, H=100, L=3000) ---
      final resMax = GeometricConstraintSolver.solve(
        document: baselineStraight,
        parameterOverrides: {
          'width': 600.0,
          'height': 100.0,
          'length': 3000.0,
        },
      );
      expect(resMax.success, isTrue);
      final docMax = resMax.updatedDocument;
      expect(docMax.parameters['width'], closeTo(600.0, 1e-2));
      expect(docMax.parameters['length'], closeTo(3000.0, 1e-2));
    });

    test('3. Rigid feature protection guarantees zero distortion or ovalization across scaling', () {
      final baselineBend = TopologicalZoneMorpher.createBaselineBend90(
        width: 100.0,
        height: 50.0,
      );

      final initialPunches = baselineBend.punches;
      expect(initialPunches, isNotEmpty);

      // Scale up significantly (W=500, R=250, H=100)
      final res = GeometricConstraintSolver.solve(
        document: baselineBend,
        parameterOverrides: {
          'width': 500.0,
          'radius': 250.0,
          'height': 100.0,
        },
      );
      expect(res.success, isTrue);
      final morphed = res.updatedDocument;

      // Check each punch against its baseline counterpart
      for (int i = 0; i < initialPunches.length; i++) {
        final initP = initialPunches[i];
        final morphedP = morphed.punches[i];

        expect(morphedP.type, initP.type);
        expect(morphedP.widthMm, closeTo(initP.widthMm, 1e-3));
        expect(morphedP.lengthMm, closeTo(initP.lengthMm, 1e-3));
        expect(morphedP.diameterMm, closeTo(initP.diameterMm, 1e-3));
        expect(morphedP.rotationDeg, closeTo(initP.rotationDeg, 1e-3));
      }
    });

    test('4. Dual sidewall height parameters (heightA, heightB) scale correctly', () {
      final baselineStraight = TopologicalZoneMorpher.createBaselineStraight(
        width: 200.0,
        height: 50.0,
        length: 1000.0,
      );

      final res = GeometricConstraintSolver.solve(
        document: baselineStraight,
        parameterOverrides: {
          'width': 200.0,
          'heightA': 75.0,
          'heightB': 50.0,
          'height': 75.0,
        },
      );

      expect(res.success, isTrue);
      expect(res.updatedDocument.parameters['height'], closeTo(75.0, 1e-2));
    });

    test('5. Equal & Unequal Tee Multi-Branch 3-Point Validation with rigid punch protection', () {
      final baselineTee = TopologicalZoneMorpher.createBaselineTee(
        width: 100.0,
        branchWidth: 100.0,
        height: 50.0,
      );
      final initialPunches = baselineTee.punches;
      expect(initialPunches, isNotEmpty);

      // --- Point 1: Scale main run & branch width (W=200, Bw=150, H=50) ---
      final resNominal = GeometricConstraintSolver.solve(
        document: baselineTee,
        parameterOverrides: {
          'width': 200.0,
          'branchWidth': 150.0,
          'height': 50.0,
        },
      );
      expect(resNominal.success, isTrue);
      final docNominal = resNominal.updatedDocument;
      expect(docNominal.parameters['width'], closeTo(200.0, 1e-2));
      expect(docNominal.parameters['branchWidth'], closeTo(150.0, 1e-2));

      // Check slot dimensions are preserved
      for (int i = 0; i < initialPunches.length; i++) {
        final initP = initialPunches[i];
        final morphedP = docNominal.punches[i];
        expect(morphedP.widthMm, closeTo(initP.widthMm, 1e-3));
        expect(morphedP.lengthMm, closeTo(initP.lengthMm, 1e-3));
      }

      // --- Point 2: Scale up both branches (W=300, Bw=200, H=75) ---
      final resLarge = GeometricConstraintSolver.solve(
        document: baselineTee,
        parameterOverrides: {
          'width': 300.0,
          'branchWidth': 200.0,
          'height': 75.0,
        },
      );
      expect(resLarge.success, isTrue);
      final docLarge = resLarge.updatedDocument;
      expect(docLarge.parameters['width'], closeTo(300.0, 1e-2));
      expect(docLarge.parameters['branchWidth'], closeTo(200.0, 1e-2));
      for (int i = 0; i < initialPunches.length; i++) {
        expect(docLarge.punches[i].widthMm, closeTo(initialPunches[i].widthMm, 1e-3));
        expect(docLarge.punches[i].lengthMm, closeTo(initialPunches[i].lengthMm, 1e-3));
      }
    });

    test('6. 4-Way Cross (cableTrayCross) 3-Point Validation with 4-arm symmetry and rigid punch protection', () {
      final baselineCross = TopologicalZoneMorpher.createBaselineCross(
        widthMain: 100.0,
        widthBranch: 100.0,
        height: 50.0,
      );
      expect(baselineCross.outerContour.length, 12);
      expect(baselineCross.punches.length, 4);

      // --- Point 1: Nominal Scale (W_main=200, W_branch=150, H=50) ---
      final resNominal = GeometricConstraintSolver.solve(
        document: baselineCross,
        parameterOverrides: {
          'widthMain': 200.0,
          'widthBranch': 150.0,
          'height': 50.0,
        },
      );
      expect(resNominal.success, isTrue);
      final docNominal = resNominal.updatedDocument;
      expect(docNominal.parameters['widthMain'], closeTo(200.0, 1e-2));
      expect(docNominal.parameters['widthBranch'], closeTo(150.0, 1e-2));
      expect(docNominal.outerContour.length, 12);

      // All 4 slot punches must maintain exact punch dimensions
      for (final p in docNominal.punches) {
        expect(p.widthMm, anyOf(closeTo(30.0, 1e-2), closeTo(7.0, 1e-2)));
        expect(p.lengthMm, anyOf(closeTo(30.0, 1e-2), closeTo(7.0, 1e-2)));
      }

      // --- Point 2: Symmetrical Expansion (W_main=300, W_branch=300, H=75) ---
      final resLarge = GeometricConstraintSolver.solve(
        document: baselineCross,
        parameterOverrides: {
          'widthMain': 300.0,
          'widthBranch': 300.0,
          'height': 75.0,
        },
      );
      expect(resLarge.success, isTrue);
      final docLarge = resLarge.updatedDocument;
      expect(docLarge.parameters['widthMain'], closeTo(300.0, 1e-2));
      expect(docLarge.parameters['widthBranch'], closeTo(300.0, 1e-2));
      for (final p in docLarge.punches) {
        expect(p.widthMm, anyOf(closeTo(30.0, 1e-2), closeTo(7.0, 1e-2)));
        expect(p.lengthMm, anyOf(closeTo(30.0, 1e-2), closeTo(7.0, 1e-2)));
      }
    });

    test('7. Concentric Reducer (cableTrayReducer) Scaling with rigid punch protection', () {
      final baselineReducer = TopologicalZoneMorpher.createBaselineReducer(
        widthIn: 100.0,
        widthOut: 50.0,
        height: 50.0,
        length: 150.0,
      );

      final initialPunches = baselineReducer.punches;
      expect(initialPunches.length, 4);

      final res = GeometricConstraintSolver.solve(
        document: baselineReducer,
        parameterOverrides: {
          'widthIn': 200.0,
          'widthOut': 100.0,
          'length': 200.0,
          'height': 50.0,
        },
      );
      expect(res.success, isTrue);
      final doc = res.updatedDocument;
      expect(doc.parameters['widthIn'], closeTo(200.0, 1e-2));
      expect(doc.parameters['widthOut'], closeTo(100.0, 1e-2));

      // Punches must retain original dimensions
      for (int i = 0; i < initialPunches.length; i++) {
        expect(doc.punches[i].widthMm, closeTo(initialPunches[i].widthMm, 1e-3));
        expect(doc.punches[i].lengthMm, closeTo(initialPunches[i].lengthMm, 1e-3));
      }
    });
  });
}
