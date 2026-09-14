
import 'package:flutter_test/flutter_test.dart';

import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';

import 'package:trufold_studio/sheet_metal_studio/models/cad_constraint.dart';

import 'package:trufold_studio/sheet_metal_studio/models/constraints/constraint_definition.dart';

import 'package:trufold_studio/sheet_metal_studio/models/constraints/stable_geometry_reference.dart';

import 'package:trufold_studio/sheet_metal_studio/engine/constraints/contour_topology_classifier.dart';

import 'package:trufold_studio/sheet_metal_studio/engine/constraints/geometric_constraint_solver.dart';

import 'package:trufold_studio/sheet_metal_studio/engine/topological_zone_morpher.dart';



void main() {

  group('Multi-Branch Contour Solving Tests (Step 2 - SET 17 & 19)', () {

    test('1. ContourTopologyClassifier accurately identifies all fitting topologies', () {

      // A. Rectangular flat blank

      final rectContour = [

        const CadPoint2D(0, 0),

        const CadPoint2D(500, 0),

        const CadPoint2D(500, 300),

        const CadPoint2D(0, 300),

      ];

      expect(ContourTopologyClassifier.classify(rectContour), ContourTopologyType.rectangular);



      // B. Cable Tray Tee (from baseline)

      final teeDoc = TopologicalZoneMorpher.createBaselineTee(width: 100, height: 50, branchWidth: 100);

      expect(ContourTopologyClassifier.classify(teeDoc.outerContour, teeDoc.bends, teeDoc), ContourTopologyType.tBranch);



      // C. Cable Tray Reducer (from baseline)

      final reducerDoc = TopologicalZoneMorpher.createBaselineReducer(widthIn: 150, widthOut: 100, height: 50);

      expect(ContourTopologyClassifier.classify(reducerDoc.outerContour, reducerDoc.bends, reducerDoc), ContourTopologyType.taperedReducer);



      // D. Cable Tray 90° Flat Bend

      final bendDoc = TopologicalZoneMorpher.createBaselineBend90(width: 100, height: 50);

      expect(ContourTopologyClassifier.classify(bendDoc.outerContour, bendDoc.bends, bendDoc), ContourTopologyType.lBend);

    });



    test('2. Unequal Tee 100x50x100 -> 300x50x150 multi-branch morphing preserves miters and coupler punches', () {

      final baselineTee = TopologicalZoneMorpher.createBaselineTee(

        width: 100.0,

        height: 50.0,

        branchWidth: 100.0,

      );



      expect(baselineTee.punches.length, greaterThanOrEqualTo(6));



      // Solve with overrides: main width 300, branch width 150

      final result = GeometricConstraintSolver.solve(

        document: baselineTee,

        parameterOverrides: {

          'width': 300.0,

          'branchWidth': 150.0,

        },

      );



      expect(result.success, isTrue);

      final morphed = result.updatedDocument;



      // 1. Verify bounds

      double minX = double.infinity, maxX = -double.infinity;

      double minY = double.infinity, maxY = -double.infinity;

      for (final p in morphed.outerContour) {

        if (p.x < minX) minX = p.x;

        if (p.x > maxX) maxX = p.x;

        if (p.y < minY) minY = p.y;

        if (p.y > maxY) maxY = p.y;

      }



      // Main run length expanded by branch delta (+50mm from 300mm -> 350mm)

      expect(maxX - minX, closeTo(350.0, 1e-2));



      // 2. Verify branch opening distance is exactly 150mm

      final branchBends = morphed.bends.where((b) => b.id.contains('BRANCH')).toList();

      expect(branchBends.length, 2);

      final branchWidthMeasured = (branchBends[1].p1.x - branchBends[0].p1.x).abs();

      expect(branchWidthMeasured, closeTo(150.0, 1e-2));



      // 3. Verify flange wall height remains 50mm

      final botFlangeBend = morphed.bends.firstWhere((b) => b.id == 'BEND_MAIN_BOT');

      expect(botFlangeBend.p1.y - minY, closeTo(50.0, 1e-2));



      // 4. Verify coupler punch spacing on left flange

      final leftPunches = morphed.punches.where((p) => p.center.x < 30.0).toList();

      expect(leftPunches.length, greaterThanOrEqualTo(2));

      for (final p in morphed.punches) {

        expect(p.widthMm, anyOf(closeTo(30.0, 1e-2), closeTo(7.0, 1e-2)));

        expect(p.lengthMm, anyOf(closeTo(30.0, 1e-2), closeTo(7.0, 1e-2)));

      }

    });



    test('3. Reducer 150x50x100 -> 200x50x50 maintains linear straight transition taper and punch sizes', () {

      final baselineReducer = TopologicalZoneMorpher.createBaselineReducer(

        widthIn: 150.0,

        widthOut: 100.0,

        height: 50.0,

        length: 200.0,

      );



      final result = GeometricConstraintSolver.solve(

        document: baselineReducer,

        parameterOverrides: {

          'widthIn': 200.0,

          'widthOut': 50.0,

        },

      );



      expect(result.success, isTrue);

      final morphed = result.updatedDocument;



      // Overall length remains straightLead * 2 + length = 280mm

      double minX = double.infinity, maxX = -double.infinity;

      for (final p in morphed.outerContour) {

        if (p.x < minX) minX = p.x;

        if (p.x > maxX) maxX = p.x;

      }

      expect(maxX - minX, closeTo(280.0, 1e-2));



      // Coupler punches retain original slot dimensions

      for (final p in morphed.punches) {

        expect(p.widthMm, closeTo(25.0, 1e-2));

        expect(p.lengthMm, closeTo(7.0, 1e-2));

      }



      // Parameters updated in document

      expect(morphed.parameters['widthIn'], closeTo(200.0, 1e-2));

      expect(morphed.parameters['widthOut'], closeTo(50.0, 1e-2));

    });



    test('4. Conflict detection rejects physically impossible fitting dimensions', () {

      final baselineTee = TopologicalZoneMorpher.createBaselineTee(

        width: 100.0,

        height: 50.0,

        branchWidth: 100.0,

      );



      // Attempt to set branchWidth wider than total main run length (500mm > 300mm)

      final conflictResult = GeometricConstraintSolver.solve(

        document: baselineTee,

        overrideConstraints: [

          const ConstraintDefinition(

            id: 'IMP_BRANCH_WIDTH',

            type: CadConstraintType.distance,

            references: [EntityRef(entityId: 'EDGE_BRANCH_LEFT'), EntityRef(entityId: 'EDGE_BRANCH_RIGHT')],

            targetValue: 500.0,

            parameterId: 'branchWidth',

          ),

        ],

      );



      expect(conflictResult.success, isFalse);

      expect(conflictResult.violatedConstraints.isNotEmpty, isTrue);



      // Negative dimension

      final negativeResult = GeometricConstraintSolver.solve(

        document: baselineTee,

        overrideConstraints: [

          const ConstraintDefinition(

            id: 'NEG_WIDTH',

            type: CadConstraintType.distance,

            references: [EntityRef.edgeBottom, EntityRef.edgeTop],

            targetValue: -50.0,

            parameterId: 'width',

          ),

        ],

      );

      expect(negativeResult.success, isFalse);

    });

  });

}

