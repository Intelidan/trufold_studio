import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/dds/dds_instance_evaluator.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/dds/dds_template_resolver.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/dds/dsf_library_service.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/dxf_exporter.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/ladder/ladder_assembly_generator.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/ladder/ladder_two_pitch_solver.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_geometry.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dds/dds_product_instance.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cnc_punch_primitive.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dxf_fitting_metadata.dart';
import 'package:trufold_studio/sheet_metal_studio/models/ladder/ladder_assembly_parameters.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';

void main() {
  group('LadderTwoPitchSolver', () {
    test('solves standard 3000mm ladder with equalized pitch', () {
      const params = LadderAssemblyParameters(
        length: 3000.0,
        endMarginPitch: 75.0,
        intermediateTargetPitch: 250.0,
        pitchMode: RungPitchMode.equalizedPitch,
      );

      final result = LadderTwoPitchSolver.solve(params);

      expect(result.isValid, isTrue);
      expect(result.effectiveSpan, equals(2850.0));
      expect(result.bayCount, equals(11));
      expect(result.rungCount, equals(12));
      expect(result.actualIntermediatePitch, closeTo(259.09, 0.01));
      expect(result.effectiveEndMargin, equals(75.0));

      expect(result.rungStationsX.first, equals(75.0));
      expect(result.rungStationsX.last, equals(2925.0));
      expect(result.rungStationsX.length, equals(12));
    });

    test('solves 3000mm ladder with fixed pitch mode', () {
      const params = LadderAssemblyParameters(
        length: 3000.0,
        endMarginPitch: 75.0,
        intermediateTargetPitch: 250.0,
        pitchMode: RungPitchMode.fixedPitch,
      );

      final result = LadderTwoPitchSolver.solve(params);

      expect(result.isValid, isTrue);
      expect(result.actualIntermediatePitch, equals(250.0));
      expect(result.bayCount, equals(11));
      expect(result.rungCount, equals(12));
      // Used span = 11 * 250 = 2750, floating margin = (3000 - 2750) / 2 = 125mm
      expect(result.effectiveEndMargin, equals(125.0));
      expect(result.rungStationsX.first, equals(125.0));
      expect(result.rungStationsX.last, equals(2875.0));
    });

    test('warns when end margin is too small (<50mm)', () {
      const params = LadderAssemblyParameters(
        length: 3000.0,
        endMarginPitch: 30.0,
      );

      final result = LadderTwoPitchSolver.solve(params);
      expect(result.validationWarnings.any((w) => w.contains('50mm')), isTrue);
    });
  });

  group('LadderAssemblyGenerator - Direct Inside Weld', () {
    test('generates flush rungs and solid side rails without slots', () {
      const params = LadderAssemblyParameters(
        width: 600.0,
        height: 100.0,
        length: 3000.0,
        thickness: 2.0,
        flangeWidth: 32.0,
        jointMethod: LadderRungJointMethod.directInsideWeld,
      );

      final assembly = LadderAssemblyGenerator.generateStraightLadder(params);

      // 1. Rung Cut Length equals nominal width
      expect(params.physicalRungCutLength, equals(600.0));
      expect(assembly.rungBlank.flatBlankLength, equals(600.0));

      // 2. Rails have NO pass-through slots
      final leftSlots = assembly.leftRailBlank.geometries.whereType<CadRectangle2D>();
      final rightSlots = assembly.rightRailBlank.geometries.whereType<CadRectangle2D>();
      expect(leftSlots.isEmpty, isTrue);
      expect(rightSlots.isEmpty, isTrue);

      // 3. Joints do NOT declare openings
      expect(assembly.joints.every((j) => !j.hasOpening), isTrue);
      expect(assembly.joints.every((j) => j.outsideProjection == 0.0), isTrue);

      // 4. Hardware BOM
      expect(assembly.hardwareBOM.passThroughSlotCount, equals(0));
      expect(assembly.hardwareBOM.weldJointCount, equals(24));
      expect(assembly.hardwareBOM.spliceCouplerCount, equals(2));
      expect(assembly.hardwareBOM.couplerBoltCount, equals(8));
      expect(assembly.hardwareBOM.holdDownClampCount, equals(2));
      expect(assembly.hardwareBOM.holdDownBoltCount, equals(2));
    });
  });

  group('LadderAssemblyGenerator - Pass-Through + Outside Weld', () {
    test('generates protruding rungs and punched rail slots', () {
      const params = LadderAssemblyParameters(
        width: 600.0,
        height: 100.0,
        length: 3000.0,
        thickness: 2.0,
        outsideWeldProjection: 3.5,
        passThroughClearance: 1.0,
        jointMethod: LadderRungJointMethod.passThroughOutsideWeld,
      );

      final assembly = LadderAssemblyGenerator.generateStraightLadder(params);

      // 1. Rung Cut Length = W + 2*T + 2*Projection = 600 + 4 + 7 = 611.0mm
      expect(params.physicalRungCutLength, equals(611.0));
      expect(assembly.rungBlank.flatBlankLength, equals(611.0));

      // 2. Rails receive 42x22mm rectangular slots for each rung
      final leftSlots = assembly.leftRailBlank.geometries.whereType<CadRectangle2D>().toList();
      final rightSlots = assembly.rightRailBlank.geometries.whereType<CadRectangle2D>().toList();

      expect(leftSlots.length, equals(12));
      expect(rightSlots.length, equals(12));
      expect(leftSlots.first.widthMm, equals(42.0));
      expect(leftSlots.first.heightMm, equals(22.0));

      // 3. Splice holes exist at both ends (4x Ø10mm at each end = 8 holes per rail)
      final leftHoles = assembly.leftRailBlank.geometries.whereType<CadCircle2D>().toList();
      expect(leftHoles.length, equals(8));
      expect(leftHoles.first.radius, equals(5.0)); // Ø10mm

      // 4. Joints declare openings and 3.5mm outside projection
      expect(assembly.joints.every((j) => j.hasOpening), isTrue);
      expect(assembly.joints.every((j) => j.outsideProjection == 3.5), isTrue);

      // 5. Hardware BOM
      expect(assembly.hardwareBOM.passThroughSlotCount, equals(24));
      expect(assembly.hardwareBOM.weldJointCount, equals(24));
      expect(assembly.hardwareBOM.totalSteelWeightKg, greaterThan(20.0));
    });

    test('width update recalculates rung cut length and leaves rail separation consistent', () {
      const params900 = LadderAssemblyParameters(
        width: 900.0,
        thickness: 2.0,
        outsideWeldProjection: 3.5,
        jointMethod: LadderRungJointMethod.passThroughOutsideWeld,
      );

      final assembly900 = LadderAssemblyGenerator.generateStraightLadder(params900);
      expect(params900.physicalRungCutLength, equals(911.0));
      expect(assembly900.rungBlank.flatBlankLength, equals(911.0));
      expect(assembly900.assembledMesh3D.boundWidth, greaterThan(900.0));
    });
  });

  group('LadderAccessoryGenerator - Horizontal Bends (Radial Spokes)', () {
    test('generates 90 deg horizontal bend with radial rungs and splice ports', () {
      const params = LadderAssemblyParameters(
        width: 600.0,
        height: 100.0,
        thickness: 2.0,
        jointMethod: LadderRungJointMethod.directInsideWeld,
      );

      final bend = LadderAssemblyGenerator.generateHorizontalBend(
        angleDeg: 90.0,
        radiusMm: 300.0,
        params: params,
      );

      expect(bend.rungs.length, greaterThanOrEqualTo(3));
      // Radial rungs have constant cut length equal to width
      expect(bend.rungs.first.cutLength, equals(600.0));
      expect(bend.splicePorts.length, equals(2));
      expect(bend.splicePorts.first.id, equals('port_1_inlet'));
      expect(bend.splicePorts.last.id, equals('port_2_outlet'));

      // 3D assembly mesh
      expect(bend.assembledMesh3D.polygons.isNotEmpty, isTrue);
      expect(bend.hardwareBOM.spliceCouplerCount, equals(2));
    });

    test('generates 45 deg bend with pass-through outside weld slots', () {
      const params = LadderAssemblyParameters(
        width: 600.0,
        thickness: 2.0,
        outsideWeldProjection: 3.5,
        jointMethod: LadderRungJointMethod.passThroughOutsideWeld,
      );

      final bend = LadderAssemblyGenerator.generateHorizontalBend(
        angleDeg: 45.0,
        radiusMm: 300.0,
        params: params,
      );

      expect(bend.rungs.first.cutLength, equals(611.0));
      expect(bend.joints.every((j) => j.hasOpening), isTrue);
      expect(bend.hardwareBOM.passThroughSlotCount, greaterThan(0));
    });
  });

  group('LadderAccessoryGenerator - Inside & Outside Risers (Slope Stations)', () {
    test('generates 90 deg inside riser with elevation curve and parallel rungs', () {
      const params = LadderAssemblyParameters(
        width: 450.0,
        height: 100.0,
        thickness: 2.0,
        jointMethod: LadderRungJointMethod.directInsideWeld,
      );

      final riser = LadderAssemblyGenerator.generateRiser(
        angleDeg: 90.0,
        radiusMm: 300.0,
        isInsideRiser: true,
        params: params,
      );

      expect(riser.rungs.length, greaterThanOrEqualTo(2));
      expect(riser.rungs.first.cutLength, equals(450.0));
      expect(riser.splicePorts.length, equals(2));
      expect(riser.assembledMesh3D.boundHeight, greaterThan(300.0));
    });

    test('generates 90 deg outside riser with convex curve and outside welds', () {
      const params = LadderAssemblyParameters(
        width: 600.0,
        height: 100.0,
        thickness: 2.0,
        outsideWeldProjection: 3.5,
        jointMethod: LadderRungJointMethod.passThroughOutsideWeld,
      );

      final riser = LadderAssemblyGenerator.generateRiser(
        angleDeg: 90.0,
        radiusMm: 300.0,
        isInsideRiser: false,
        params: params,
      );

      expect(riser.rungs.first.cutLength, equals(611.0));
      expect(riser.joints.every((j) => j.hasOpening), isTrue);
      expect(riser.splicePorts.length, equals(2));
    });
  });

  group('LadderAccessoryGenerator - Reducers (Linearly Tapered Rungs)', () {
    test('generates concentric reducer with linearly decreasing rung cut lengths', () {
      const params = LadderAssemblyParameters(
        width: 600.0,
        height: 100.0,
        thickness: 2.0,
        jointMethod: LadderRungJointMethod.directInsideWeld,
      );

      final reducer = LadderAssemblyGenerator.generateReducer(
        width1: 600.0,
        width2: 300.0,
        length: 500.0,
        alignment: 'straight',
        params: params,
      );

      expect(reducer.rungs.length, greaterThanOrEqualTo(2));
      // First rung is wider than last rung
      expect(reducer.rungs.first.cutLength, greaterThan(reducer.rungs.last.cutLength));
      expect(reducer.splicePorts.length, equals(2));
      expect(reducer.splicePorts[0].width, equals(600.0));
      expect(reducer.splicePorts[1].width, equals(300.0));
    });

    test('generates left-hand reducer with aligned left rail', () {
      const params = LadderAssemblyParameters(
        width: 600.0,
        height: 100.0,
        thickness: 2.0,
        jointMethod: LadderRungJointMethod.passThroughOutsideWeld,
      );

      final reducer = LadderAssemblyGenerator.generateReducer(
        width1: 600.0,
        width2: 300.0,
        length: 500.0,
        alignment: 'left',
        params: params,
      );

      expect(reducer.rungs.every((r) => r.cutLength > 300.0 && r.cutLength <= 611.0), isTrue);
      expect(reducer.assembledMesh3D.polygons.isNotEmpty, isTrue);
    });
  });

  group('LadderAccessoryGenerator - Tees and Crosses (Orthogonal Pattern)', () {
    test('generates 3-port equal tee with spine and branch rungs', () {
      const params = LadderAssemblyParameters(
        width: 600.0,
        height: 100.0,
        thickness: 2.0,
        jointMethod: LadderRungJointMethod.directInsideWeld,
      );

      final tee = LadderAssemblyGenerator.generateTee(
        mainWidth: 600.0,
        branchWidth: 600.0,
        radiusMm: 300.0,
        params: params,
      );

      expect(tee.splicePorts.length, equals(3));
      expect(tee.hardwareBOM.spliceCouplerCount, equals(3));
      expect(tee.hardwareBOM.couplerBoltCount, equals(12));
      expect(tee.rungs.any((r) => r.orientationAngleRad > 0.1), isTrue); // Has branch rung
    });

    test('generates 4-port equal cross with orthogonal 4-way rungs', () {
      const params = LadderAssemblyParameters(
        width: 600.0,
        height: 100.0,
        thickness: 2.0,
        jointMethod: LadderRungJointMethod.passThroughOutsideWeld,
      );

      final cross = LadderAssemblyGenerator.generateCross(
        mainWidth: 600.0,
        branchWidth: 600.0,
        radiusMm: 300.0,
        params: params,
      );

      expect(cross.splicePorts.length, equals(4));
      expect(cross.hardwareBOM.spliceCouplerCount, equals(4));
      expect(cross.hardwareBOM.couplerBoltCount, equals(16));
    });
  });

  group('DdsInstanceEvaluator - Ladder & Accessories Evaluation', () {
    test('evaluates straight ladder instance with generative multi-body takeoff', () {
      const instance = DdsProductInstance(
        instanceId: 'inst_lad_1',
        productName: 'Cable Ladder',
        productCode: 'LAD-600',
        templateReference: DdsTemplateReference(templateId: 'cable_ladder', baselineFileName: 'ladder.dsf'),
        instanceParameters: {
          'width': 600.0,
          'height': 100.0,
          'length': 3000.0,
          'thickness': 2.0,
          'rung_joint_method': 1.0, // passThroughOutsideWeld
        },
        coverConfiguration: DdsCoverConfig(included: false),
      );

      final baselineDoc = DsfDocument.sampleCableTray();
      final eval = DdsInstanceEvaluator.evaluate(instance: instance, baselineDoc: baselineDoc);

      expect(eval.calculatedTakeoff.estimatedNetWeightKg, greaterThan(20.0));
      expect(eval.scaledPorts.length, equals(2));
      expect(eval.baseMesh3D.polygons.isNotEmpty, isTrue);
      expect(eval.scaledBaseDocument.metadata.containsKey('ladderAssembly'), isTrue);
    });

    test('evaluates ladder 90 deg bend instance through accessory generator pipeline', () {
      const instance = DdsProductInstance(
        instanceId: 'inst_bend_1',
        productName: 'Ladder 90 Deg Bend',
        productCode: 'LAD-BEND-90',
        templateReference: DdsTemplateReference(templateId: 'ladder_bend_90', baselineFileName: 'ladder_bend_90.dsf'),
        instanceParameters: {
          'width': 600.0,
          'height': 100.0,
          'angle': 90.0,
          'radius': 300.0,
          'thickness': 2.0,
          'rung_joint_method': 0.0, // directInsideWeld
        },
        coverConfiguration: DdsCoverConfig(included: false),
      );

      final baselineDoc = DsfDocument.sampleCableTray();
      final eval = DdsInstanceEvaluator.evaluate(instance: instance, baselineDoc: baselineDoc);

      expect(eval.calculatedTakeoff.estimatedNetWeightKg, greaterThan(5.0));
      expect(eval.scaledPorts.length, equals(2));
      expect(eval.baseMesh3D.polygons.isNotEmpty, isTrue);
      expect(eval.scaledBaseDocument.metadata.containsKey('ladderAssembly'), isTrue);
    });
  });

  group('LadderAssemblyGenerator - Multi-Blank CAM DXF Export', () {
    test('exports all constituent blanks as individual DXF files and combined nested DXF', () {
      const params = LadderAssemblyParameters(
        width: 600.0,
        height: 100.0,
        length: 3000.0,
        thickness: 2.0,
        outsideWeldProjection: 3.5,
        includeCover: true,
        jointMethod: LadderRungJointMethod.passThroughOutsideWeld,
      );

      final ladder = LadderAssemblyGenerator.generateStraightLadder(params);

      // 1. Export individual files
      final files = DxfExporter.exportLadderAssemblyDxfFiles(ladder);
      expect(files.containsKey('${ladder.id}_left_rail.dxf'), isTrue);
      expect(files.containsKey('${ladder.id}_right_rail.dxf'), isTrue);
      expect(files.containsKey('${ladder.id}_rung_blank.dxf'), isTrue);
      expect(files.containsKey('${ladder.id}_cover.dxf'), isTrue);

      for (final content in files.values) {
        expect(content.contains('SECTION'), isTrue);
        expect(content.contains('ENTITIES'), isTrue);
        expect(content.contains('EOF'), isTrue);
      }

      // 2. Export combined production nesting DXF
      final combinedDxf = DxfExporter.exportLadderAssemblyCombinedDxf(ladder);
      expect(combinedDxf.contains('LEFT SIDE RAIL BLANK'), isTrue);
      expect(combinedDxf.contains('RIGHT SIDE RAIL BLANK'), isTrue);
      expect(combinedDxf.contains('RUNG BLANK (40×20 C-CHANNEL)'), isTrue);
      expect(combinedDxf.contains('LADDER FORMED COVER BLANK'), isTrue);
      expect(combinedDxf.contains('EOF'), isTrue);
    });
  });

  group('DdsTemplateResolver & DsfLibraryService - Ladder Discovery & Matching', () {
    test('matches Excel spreadsheet description keywords to correct ladder templates', () {
      expect(DdsTemplateResolver.matchByDescription('CABLE LADDER 600X100 3000MM')?.templateId, equals('ladder_straight'));
      expect(DdsTemplateResolver.matchByDescription('LADDER 90 DEG BEND R300')?.templateId, equals('ladder_bend_90'));
      expect(DdsTemplateResolver.matchByDescription('45 DEG LADDER ELBOW')?.templateId, equals('ladder_bend_45'));
      expect(DdsTemplateResolver.matchByDescription('LADDER INSIDE RISER 90')?.templateId, equals('ladder_inside_riser_90'));
      expect(DdsTemplateResolver.matchByDescription('LADDER OUTSIDE RISER 90')?.templateId, equals('ladder_outside_riser_90'));
      expect(DdsTemplateResolver.matchByDescription('LADDER REDUCER 600 TO 300')?.templateId, equals('ladder_reducer'));
      expect(DdsTemplateResolver.matchByDescription('LADDER EQUAL TEE')?.templateId, equals('ladder_equal_tee'));
      expect(DdsTemplateResolver.matchByDescription('LADDER 4-WAY CROSS')?.templateId, equals('ladder_equal_cross'));
    });

    test('synthesizes non-null baseline DSF documents for ladder templates without disk files', () {
      final doc = DdsTemplateResolver.resolveTemplateSync(DdsTemplateResolver.createReference('ladder_straight'));
      expect(doc, isNotNull);
      expect(doc!.productType, equals('cable_ladder'));
      expect(doc.metadata['isLadderAssembly'], isTrue);
    });

    test('loads genuine stored DSF templates in DsfLibraryService and verifies systemCategory and componentType', () {
      DsfLibraryService.clearCache();
      final items = DsfLibraryService.loadAllTemplatesSync();
      expect(items.isNotEmpty, isTrue);

      // Verify that stored templates have genuine system categories (Cable Trays, Cable Trunking)
      final trayItems = items.where((i) => i.systemCategory == 'Cable Trays').toList();
      final trunkingItems = items.where((i) => i.systemCategory == 'Cable Trunking').toList();
      expect(trayItems.isNotEmpty, isTrue);
      expect(trunkingItems.isNotEmpty, isTrue);

      for (final item in items) {
        expect(item.componentType.isNotEmpty, isTrue);
        expect(item.fittingType.isNotEmpty, isTrue);
      }
    });

    test('creates and saves multi-blank assembly DSF document to disk', () async {
      const params = LadderAssemblyParameters(
        width: 600.0,
        height: 100.0,
        length: 3000.0,
        thickness: 2.0,
        outsideWeldProjection: 3.5,
        jointMethod: LadderRungJointMethod.passThroughOutsideWeld,
      );

      final assembly = LadderAssemblyGenerator.generateStraightLadder(params);
      final dsfDoc = LadderAssemblyGenerator.createAssemblyDsfDocument(assembly);

      expect(dsfDoc.productType, equals('cable_ladder'));
      expect(dsfDoc.bends.length, greaterThan(0));
      expect(dsfDoc.punches.length, greaterThan(0));
      expect(dsfDoc.cutLines.length, greaterThan(0));
      expect(dsfDoc.metadata['isLadderAssembly'], isTrue);

      final savedFile = await LadderAssemblyGenerator.saveAssemblyDsfFile(
        assembly,
        fileName: 'test_ladder_save.dsf',
        targetDirectory: 'build/test_dsf_templates/ladders',
      );

      expect(savedFile.existsSync(), isTrue);
      final content = await savedFile.readAsString();
      expect(content.contains('cable_ladder'), isTrue);
      expect(content.contains('OUTLINE'), isTrue);

      // Clean up test file
      if (savedFile.existsSync()) savedFile.deleteSync();
    });
  });

  group('Cable Ladder Assembly - Enhancements & Datasheet Compliance', () {
    test('supports angular/segmented profile style vs curved sweep on accessories', () {
      const segParams = LadderAssemblyParameters(
        width: 500.0,
        height: 100.0,
        thickness: 2.0,
        accessoryStyle: LadderAccessoryStyle.segmented,
      );
      final segBend = LadderAssemblyGenerator.generateHorizontalBend(
        params: segParams,
        angleDeg: 90.0,
        radiusMm: 300.0,
      );
      expect(segBend.id.contains('SEGMENTED'), isTrue);
      expect(segBend.productName.contains('Segmented Horizontal Bend'), isTrue);

      const curvedParams = LadderAssemblyParameters(
        width: 500.0,
        height: 100.0,
        thickness: 2.0,
        accessoryStyle: LadderAccessoryStyle.curved,
      );
      final curvedBend = LadderAssemblyGenerator.generateHorizontalBend(
        params: curvedParams,
        angleDeg: 90.0,
        radiusMm: 300.0,
      );
      expect(curvedBend.id.contains('CURVED'), isTrue);
      expect(curvedBend.productName.contains('Horizontal Bend'), isTrue);
      expect(curvedBend.productName.contains('Segmented'), isFalse);
    });

    test('generates true 25x14mm obround slots on rungs and exports CAM punches properly', () {
      const params = LadderAssemblyParameters(
        width: 600.0,
        height: 100.0,
        length: 3000.0,
        thickness: 2.0,
      );
      final assembly = LadderAssemblyGenerator.generateStraightLadder(params);
      final slots = assembly.rungBlank.geometries.whereType<CadSlot2D>().toList();
      expect(slots.isNotEmpty, isTrue);
      for (final slot in slots) {
        expect(slot.lengthMm, equals(25.0));
        expect(slot.widthMm, equals(14.0));
      }

      final doc = LadderAssemblyGenerator.createAssemblyDsfDocument(assembly);
      final punchSlot = doc.punches.where((p) => p.type == PunchType.obroundSlot).toList();
      expect(punchSlot.isNotEmpty, isTrue);
      expect(punchSlot.first.lengthMm, equals(25.0));
      expect(punchSlot.first.widthMm, equals(14.0));
    });

    test('detects straight ladder and accessories correctly in DxfFittingMetadata without bend fallback', () {
      const params = LadderAssemblyParameters(
        width: 500.0,
        height: 100.0,
        length: 3000.0,
        thickness: 2.0,
      );
      final straightAssembly = LadderAssemblyGenerator.generateStraightLadder(params);
      final straightDoc = LadderAssemblyGenerator.createAssemblyDsfDocument(straightAssembly);

      final straightMeta = DxfFittingMetadata.fromDocument(straightDoc);
      expect(straightMeta, isNotNull);
      expect(straightMeta!.isLadder, isTrue);
      expect(straightMeta.category, equals('Length'));
      expect(straightMeta.product, equals('Ladder'));

      final segBendAssembly = LadderAssemblyGenerator.generateHorizontalBend(
        params: params.copyWith(accessoryStyle: LadderAccessoryStyle.segmented),
        angleDeg: 90.0,
      );
      final bendDoc = LadderAssemblyGenerator.createAssemblyDsfDocument(segBendAssembly);
      final bendMeta = DxfFittingMetadata.fromDocument(bendDoc);
      expect(bendMeta, isNotNull);
      expect(bendMeta!.isLadder, isTrue);
      expect(bendMeta.category, equals('Ladder Accessories'));
      expect(bendMeta.product, equals(FittingProductType.bend));
    });

    test('synthesizes multi-body ladder assembly from DSF document via generateFromDocument', () {
      const params = LadderAssemblyParameters(
        width: 500.0,
        height: 100.0,
        length: 3000.0,
        thickness: 2.0,
      );
      final originalAssembly = LadderAssemblyGenerator.generateStraightLadder(params);
      final doc = LadderAssemblyGenerator.createAssemblyDsfDocument(originalAssembly);

      final reconstructed = LadderAssemblyGenerator.generateFromDocument(doc);
      expect(reconstructed, isNotNull);
      expect(reconstructed.parameters.width, equals(500.0));
      expect(reconstructed.parameters.height, equals(100.0));
      expect(reconstructed.assembledMesh3D.allPolygons.isNotEmpty, isTrue);
      expect(reconstructed.rungs.length, equals(originalAssembly.rungs.length));
    });

    test('2D sketch items are oriented vertically and positioned side-by-side along X', () {
      const params = LadderAssemblyParameters(
        width: 300.0,
        height: 100.0,
        length: 3000.0,
        thickness: 2.0,
      );
      final assembly = LadderAssemblyGenerator.generateStraightLadder(params);
      final doc = LadderAssemblyGenerator.createAssemblyDsfDocument(assembly);

      // Verify that cutlines have their long dimension oriented vertically along Y
      double maxY = 0.0;
      double maxX = 0.0;
      for (final line in doc.cutLines) {
        if (line.p1.y > maxY) maxY = line.p1.y;
        if (line.p2.y > maxY) maxY = line.p2.y;
        if (line.p1.x > maxX) maxX = line.p1.x;
        if (line.p2.x > maxX) maxX = line.p2.x;
      }

      // Height (length 3000mm) is along Y, while width (multiple blanks side-by-side) is along X
      expect(maxY, closeTo(3000.0, 50.0));
      expect(maxX, greaterThan(300.0)); // At least left rail (140) + right rail (140) + spacing
    });

    test('rungs are oriented right-side up with top slotted web (+Z) and downward flanges (-Z)', () {
      const params = LadderAssemblyParameters(
        width: 300.0,
        height: 100.0,
        length: 3000.0,
        thickness: 2.0,
      );
      final assembly = LadderAssemblyGenerator.generateStraightLadder(params);
      final mesh = assembly.assembledMesh3D;

      // Find top web polygons of rungs
      final topWebPolys = mesh.polygons.where((p) => p.faceId.contains('rung_') && p.normal.z > 0.9).toList();
      expect(topWebPolys.isNotEmpty, isTrue);

      // Verify true obround cutout holes in the top web
      final slottedWebs = topWebPolys.where((p) => p.holes.isNotEmpty).toList();
      expect(slottedWebs.isNotEmpty, isTrue);
      expect(slottedWebs.first.holes.first.length, greaterThanOrEqualTo(8));

      // Verify downward side flanges (normal along +/- X)
      final flangePolys = mesh.polygons.where((p) => p.faceId.contains('flange_front') || p.faceId.contains('flange_back')).toList();
      expect(flangePolys.isNotEmpty, isTrue);
    });

    test('3D model includes physical sheet thickness and RIM polygons for rails and rungs', () {
      const params = LadderAssemblyParameters(
        width: 300.0,
        height: 100.0,
        length: 3000.0,
        thickness: 2.0,
      );
      final assembly = LadderAssemblyGenerator.generateStraightLadder(params);
      final mesh = assembly.assembledMesh3D;

      // Thickness polygons must be non-empty and contain RIM_ definitions
      expect(mesh.thicknessPolygons.isNotEmpty, isTrue);
      final rimPolys = mesh.thicknessPolygons.where((p) => p.faceId.startsWith('RIM_')).toList();
      expect(rimPolys.isNotEmpty, isTrue);
      expect(rimPolys.any((p) => p.faceId.contains('top_flange_lip')), isTrue);
      expect(rimPolys.any((p) => p.faceId.contains('bottom_flange_lip')), isTrue);
      expect(rimPolys.any((p) => p.faceId.contains('port1')), isTrue);
      expect(rimPolys.any((p) => p.faceId.contains('port2')), isTrue);

      // Verify rung thickness faces (inner web, slot walls, and bottom lips)
      expect(mesh.polygons.any((p) => p.faceId.contains('top_web_inner')), isTrue);
      expect(mesh.polygons.any((p) => p.faceId.contains('flange_front_inner')), isTrue);
      expect(mesh.polygons.any((p) => p.faceId.contains('front_lip')), isTrue);
      expect(mesh.polygons.any((p) => p.faceId.contains('wall_')), isTrue);
    });


    test('eliminates yellow color artifacts across straight ladder and accessories', () {
      const params = LadderAssemblyParameters(
        width: 300.0,
        height: 100.0,
        length: 3000.0,
        thickness: 2.0,
        jointMethod: LadderRungJointMethod.passThroughOutsideWeld,
      );
      final straightAssembly = LadderAssemblyGenerator.generateStraightLadder(params);
      const yellowColor = Color(0xFFFFB300);

      // Straight ladder
      for (final p in straightAssembly.assembledMesh3D.allPolygons) {
        expect(p.color, isNot(equals(yellowColor)));
      }

      // Horizontal bend
      final bendAssembly = LadderAssemblyGenerator.generateHorizontalBend(angleDeg: 90.0, params: params);
      for (final p in bendAssembly.assembledMesh3D.allPolygons) {
        expect(p.color, isNot(equals(yellowColor)));
      }

      // Inside riser
      final riserAssembly = LadderAssemblyGenerator.generateRiser(angleDeg: 90.0, isInsideRiser: true, params: params);
      for (final p in riserAssembly.assembledMesh3D.allPolygons) {
        expect(p.color, isNot(equals(yellowColor)));
      }
    });

    test('parameter changes morph the ladder assembly without collapsing into single channel', () {
      const params = LadderAssemblyParameters(
        width: 300.0,
        height: 100.0,
        length: 3000.0,
        thickness: 2.0,
      );
      final assembly = LadderAssemblyGenerator.generateStraightLadder(params);
      final doc = LadderAssemblyGenerator.createAssemblyDsfDocument(assembly);

      final vm = SheetMetalStudioViewModel();
      vm.loadDocument(doc);

      expect(vm.isLadderAssembly, isTrue);
      expect(vm.scalingController, isNull);

      // Verify initial full assembled mesh
      final initialMesh = vm.cachedMesh;
      expect(initialMesh, isNotNull);
      final initialRungFaces = initialMesh!.polygons.where((p) => p.faceId.contains('rung_')).length;
      expect(initialRungFaces, greaterThan(10));

      // Morph width parameter
      vm.applyCmsMorphParameter('width', 400.0);

      expect(vm.isLadderAssembly, isTrue);
      expect(vm.scalingController, isNull);
      expect(vm.document.parameters['width'], equals(400.0));

      // Verify morphed mesh still contains all assembled rungs and side rails
      final morphedMesh = vm.cachedMesh;
      expect(morphedMesh, isNotNull);
      final morphedRungFaces = morphedMesh!.polygons.where((p) => p.faceId.contains('rung_')).length;
      expect(morphedRungFaces, greaterThan(10));
      expect(morphedMesh.boundWidth, closeTo(400.0 + (2 * 32.0), 10.0));

      // Morph height parameter
      vm.applyCmsMorphParameter('height', 150.0);
      expect(vm.document.parameters['height'], equals(150.0));
      final heightMorphedMesh = vm.cachedMesh;
      expect(heightMorphedMesh, isNotNull);
      expect(heightMorphedMesh!.boundHeight, equals(150.0));
    });

    test('SS1: displays 1 copy of unique entities in 2D view and eliminates enclosing sheet', () {
      const params = LadderAssemblyParameters(
        width: 300.0,
        height: 100.0,
        length: 3000.0,
        thickness: 2.0,
      );
      final assembly = LadderAssemblyGenerator.generateStraightLadder(params);
      final doc = LadderAssemblyGenerator.createAssemblyDsfDocument(assembly);

      // Verify that artificial outer sheet is eliminated
      expect(doc.outerContour.isEmpty, isTrue);

      // Verify exactly 1 unique side rail blank and 1 unique rung blank
      expect(doc.faces.length, equals(2));
      expect(doc.faces.any((f) => f.id == 'side_rail_blank'), isTrue);
      expect(doc.faces.any((f) => f.id == 'rung_blank'), isTrue);

      // Verify quantity is clearly designated
      final railFace = doc.faces.firstWhere((f) => f.id == 'side_rail_blank');
      expect(railFace.label.contains('Qty: 2'), isTrue);
      final rungFace = doc.faces.firstWhere((f) => f.id == 'rung_blank');
      expect(rungFace.label.contains('Qty: ${assembly.rungs.length}'), isTrue);

      // Verify blankWidthMm and blankLengthMm still compute true bounds
      expect(doc.blankLengthMm, closeTo(3000.0, 1.0));
      expect(doc.blankWidthMm, greaterThan(200.0));
    });

    test('SS1: displays 1 piece of each unique entity for accessories with varying rung sizes', () {
      const reducerParams = LadderAssemblyParameters(
        width: 600.0,
        height: 100.0,
        thickness: 2.0,
      );
      final reducerAssembly = LadderAssemblyGenerator.generateReducer(
        width1: 600.0,
        width2: 300.0,
        length: 1200.0,
        alignment: 'straight',
        params: reducerParams,
      );
      final doc = LadderAssemblyGenerator.createAssemblyDsfDocument(reducerAssembly);

      // Outer bounding sheet is eliminated
      expect(doc.outerContour.isEmpty, isTrue);

      // Tapering reducer rungs should generate distinct unique rung entities
      final rungFaces = doc.faces.where((f) => f.id.startsWith('rung_blank')).toList();
      expect(rungFaces.length, greaterThan(1));
    });

    test('SS2: Two-pitch engine accepts arbitrary custom end margin and body pitch values', () {
      const params = LadderAssemblyParameters(
        width: 300.0,
        height: 100.0,
        length: 3000.0,
        thickness: 2.0,
        endMarginPitch: 62.0, // Arbitrary custom value
        intermediateTargetPitch: 280.0, // Arbitrary custom value
      );
      final assembly = LadderAssemblyGenerator.generateStraightLadder(params);
      expect(assembly.parameters.endMarginPitch, equals(62.0));
      expect(assembly.parameters.intermediateTargetPitch, equals(280.0));

      final doc = LadderAssemblyGenerator.createAssemblyDsfDocument(assembly);
      expect(doc.parameters['end_margin_pitch'], equals(62.0));
      expect(doc.parameters['rung_pitch'], equals(280.0));

      final vm = SheetMetalStudioViewModel();
      vm.loadDocument(doc);
      expect(vm.document.parameters['end_margin_pitch'], equals(62.0));
      expect(vm.document.parameters['rung_pitch'], equals(280.0));

      // Test live morph to new arbitrary values
      vm.applyCmsMorphParameter('end_margin_pitch', 85.0);
      expect(vm.document.parameters['end_margin_pitch'], equals(85.0));
      expect(vm.activeLadderAssembly!.parameters.endMarginPitch, equals(85.0));

      vm.applyCmsMorphParameter('rung_pitch', 220.0);
      expect(vm.document.parameters['rung_pitch'], equals(220.0));
      expect(vm.activeLadderAssembly!.parameters.intermediateTargetPitch, equals(220.0));
    });

    test('SS3a & SS3b & SS3c: Outside weld projection, default half body pitch, and 3D cover', () {
      // 1. By default, end margin of rungs is half the body pitch (intermediateTargetPitch / 2.0)
      final defaultParams = LadderAssemblyParameters(intermediateTargetPitch: 260.0, endMarginPitch: 130.0);
      expect(defaultParams.endMarginPitch, equals(defaultParams.intermediateTargetPitch / 2.0));

      final jsonDecoded = LadderAssemblyParameters.fromJson({'intermediateTargetPitch': 300.0});
      expect(jsonDecoded.endMarginPitch, equals(150.0)); // 300.0 / 2.0

      // 2. Ladder assembly document live morphing for outside projection (5mm, 10mm, 15mm)
      final assembly = LadderAssemblyGenerator.generateStraightLadder(
        const LadderAssemblyParameters(length: 1500.0, width: 400.0, intermediateTargetPitch: 250.0),
      );
      final doc = LadderAssemblyGenerator.createAssemblyDsfDocument(assembly);
      final vm = SheetMetalStudioViewModel();
      vm.loadDocument(doc);

      for (final proj in [5.0, 10.0, 15.0]) {
        vm.applyCmsMorphParameter('outsideWeldProjection', proj);
        expect(vm.activeLadderAssembly!.parameters.outsideWeldProjection, equals(proj));
      }

      // 3. Parametric cover in 3D for ladder assembly
      expect(vm.hasCover, isFalse);
      expect(vm.isCoverVisible3D, isFalse);

      vm.applyCmsMorphParameter('include_cover', 1.0);
      expect(vm.hasCover, isTrue);
      expect(vm.isCoverVisible3D, isTrue);
      expect(vm.coverMesh, isNotNull);
      expect(vm.currentMesh.polygons.isNotEmpty, isTrue);
    });

    test('Cable Ladder 90 deg and 45 deg bends & risers compliance (5 Key Industrial Criteria)', () {
      // 1. Rungs should have obround holes
      const passThroughParams = LadderAssemblyParameters(
        width: 400.0,
        height: 100.0,
        jointMethod: LadderRungJointMethod.passThroughOutsideWeld,
        outsideWeldProjection: 5.0,
        accessoryStyle: LadderAccessoryStyle.segmented,
      );

      final bend90 = LadderAssemblyGenerator.generateHorizontalBend(
        angleDeg: 90.0,
        radiusMm: 300.0,
        params: passThroughParams,
      );

      // Verify obround holes on rungs
      final bendRungWebs = bend90.assembledMesh3D.polygons.where((p) => p.faceId.contains('bend_rung') && p.faceId.endsWith('_top_web')).toList();
      expect(bendRungWebs.isNotEmpty, isTrue);
      for (final web in bendRungWebs) {
        expect(web.holes.isNotEmpty, isTrue); // obround slots cut out
      }

      // 2. Continuous flanges present on all rails (inner & outer, top & bottom)
      expect(bend90.assembledMesh3D.polygons.any((p) => p.faceId.startsWith('inner_rail_bottom_flange')), isTrue);
      expect(bend90.assembledMesh3D.polygons.any((p) => p.faceId.startsWith('inner_rail_top_flange')), isTrue);
      expect(bend90.assembledMesh3D.polygons.any((p) => p.faceId.startsWith('outer_rail_bottom_flange')), isTrue);
      expect(bend90.assembledMesh3D.polygons.any((p) => p.faceId.startsWith('outer_rail_top_flange')), isTrue);

      // 3. Side rail and rung solid endcaps eliminated; open port rims and physical sheet thickness present
      expect(bend90.assembledMesh3D.allPolygons.any((p) => p.faceId == 'RIM_inner_rail_lead_in'), isFalse);
      expect(bend90.assembledMesh3D.allPolygons.any((p) => p.faceId.contains('_port1_cap') || p.faceId.contains('_port2_cap')), isFalse);
      expect(bend90.assembledMesh3D.thicknessPolygons.any((p) => p.faceId == 'RIM_inner_port1_web'), isTrue);
      expect(bend90.assembledMesh3D.thicknessPolygons.any((p) => p.faceId == 'RIM_outer_port1_web'), isTrue);
      expect(bend90.assembledMesh3D.thicknessPolygons.any((p) => p.faceId == 'RIM_inner_port2_web'), isTrue);
      expect(bend90.assembledMesh3D.thicknessPolygons.any((p) => p.faceId == 'RIM_outer_port2_web'), isTrue);

      // Verify physical sheet thickness in 3D model (inner webs, inner flanges, flange lips, inner rung web)
      expect(bend90.assembledMesh3D.polygons.any((p) => p.faceId.startsWith('inner_rail_web_inner')), isTrue);
      expect(bend90.assembledMesh3D.polygons.any((p) => p.faceId.startsWith('outer_rail_web_inner')), isTrue);
      expect(bend90.assembledMesh3D.thicknessPolygons.any((p) => p.faceId.contains('inner_top_flange_lip')), isTrue);
      expect(bend90.assembledMesh3D.thicknessPolygons.any((p) => p.faceId.contains('outer_top_flange_lip')), isTrue);
      expect(bend90.assembledMesh3D.polygons.any((p) => p.faceId.contains('bend_rung') && p.faceId.endsWith('_top_web_inner')), isTrue);

      // 4. Snug pass-through slot holes punched in rail webs & visible rung outside weld projections
      final innerWebsWithHoles = bend90.assembledMesh3D.polygons.where((p) => p.faceId.startsWith('inner_rail_web') && p.holes.isNotEmpty);
      expect(innerWebsWithHoles.isNotEmpty, isTrue);
      final outerWebsWithHoles = bend90.assembledMesh3D.polygons.where((p) => p.faceId.startsWith('outer_rail_web') && p.holes.isNotEmpty);
      expect(outerWebsWithHoles.isNotEmpty, isTrue);
      expect(bend90.assembledMesh3D.polygons.any((p) => p.faceId.contains('_proj_left_top')), isTrue);
      expect(bend90.assembledMesh3D.polygons.any((p) => p.faceId.contains('_proj_right_top')), isTrue);

      // 5. V-Notch cut out (V) on flange: shifts from outer rail (inside flange) to inner rail (outside flange)
      // Inside flange: V-notch is on the outer rail top and bottom flanges
      expect(bend90.assembledMesh3D.thicknessPolygons.any((p) => p.faceId.contains('RIM_outer_top_notch')), isTrue);
      expect(bend90.assembledMesh3D.thicknessPolygons.any((p) => p.faceId.contains('RIM_inner_top_notch')), isFalse);

      // Outside flange: V-notch shifts to the inner rail
      final bend90Outside = LadderAssemblyGenerator.generateHorizontalBend(
        angleDeg: 90.0,
        radiusMm: 300.0,
        params: passThroughParams.copyWith(flangeDirection: LadderFlangeDirection.outside),
      );
      expect(bend90Outside.assembledMesh3D.thicknessPolygons.any((p) => p.faceId.contains('RIM_inner_top_notch')), isTrue);
      expect(bend90Outside.assembledMesh3D.thicknessPolygons.any((p) => p.faceId.contains('RIM_outer_top_notch')), isFalse);

      // 6. Rungs are squarely on the straight segments, not intersecting miter bend lines
      expect(bend90.rungs.length, equals(4)); // 4 straight segments for 90° bend
      final bend45 = LadderAssemblyGenerator.generateHorizontalBend(
        angleDeg: 45.0,
        radiusMm: 300.0,
        params: passThroughParams,
      );
      expect(bend45.rungs.length, equals(3)); // 3 straight segments for 45° bend

      // Verify inside & outside risers have full physical sheet thickness and open port profile rims (no solid caps)
      final insideRiser90 = LadderAssemblyGenerator.generateRiser(
        angleDeg: 90.0,
        radiusMm: 300.0,
        isInsideRiser: true,
        params: passThroughParams,
      );
      expect(insideRiser90.rungs.length, equals(4));
      expect(insideRiser90.assembledMesh3D.polygons.any((p) => p.faceId.startsWith('riser_rail_bottom_flange_l')), isTrue);
      expect(insideRiser90.assembledMesh3D.polygons.any((p) => p.faceId.startsWith('riser_rail_top_flange_l')), isTrue);
      expect(insideRiser90.assembledMesh3D.polygons.any((p) => p.faceId.startsWith('riser_rail_web_l_inner')), isTrue);
      expect(insideRiser90.assembledMesh3D.allPolygons.any((p) => p.faceId == 'RIM_riser_left_port1'), isFalse); // No solid cap
      expect(insideRiser90.assembledMesh3D.thicknessPolygons.any((p) => p.faceId == 'RIM_riser_left_port1_web'), isTrue); // Open 2mm profile rim

      final outsideRiser45 = LadderAssemblyGenerator.generateRiser(
        angleDeg: 45.0,
        radiusMm: 300.0,
        isInsideRiser: false,
        params: passThroughParams,
      );
      expect(outsideRiser45.rungs.length, equals(3));
      expect(outsideRiser45.assembledMesh3D.polygons.any((p) => p.faceId.contains('riser_rung') && p.faceId.endsWith('_top_web')), isTrue);
    });
  });
}
