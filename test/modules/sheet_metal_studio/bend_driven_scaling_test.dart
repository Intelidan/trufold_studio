import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/constraints/geometric_constraint_solver.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/structural_topology_analyzer.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/topological_zone_morpher.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_parameter.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cnc_punch_primitive.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/template_parameter_definition.dart';

void main() {
  group('Bend-Driven Parametric Scaling & Rigid Coupler Preservation Tests', () {
    test('1. Baseline inspection of 45_deg_bend_100x100.dsf', () async {
      final file = File('assets/dxf_templates/trunking_accessories/45_deg_bend_100x100.dsf');
      expect(file.existsSync(), isTrue);

      final content = await file.readAsString();
      final doc = DsfDocument.fromJson(jsonDecode(content) as Map<String, dynamic>);

      // Initial 3D fold
      final foldResult = KinematicFoldEngine.foldDocument(doc);
      expect(foldResult.polygons.isNotEmpty, isTrue);

      final topo = StructuralTopologyAnalyzer.analyze(doc);
      expect(topo.detectedPorts.length, equals(2));

      // Verify all 8 punches are obround slots with exact rigid dimensions
      expect(doc.punches.length, equals(8));
      for (final p in doc.punches) {
        expect(p.type, equals(PunchType.obroundSlot));
        expect((p.widthMm - 8.0).abs(), lessThan(1e-3));
        expect((p.lengthMm - 12.0).abs(), lessThan(1e-3));
      }
    });

    test('3. Width invariants: port mouths widen by dW, outer B1 spine length fixed, apex on bisector', () async {
      final file = File('assets/dxf_templates/trunking_accessories/45_deg_bend_100x100.dsf');
      final content = await file.readAsString();
      final doc = DsfDocument.fromJson(jsonDecode(content) as Map<String, dynamic>);

      const origW = 100.0;
      const targetW = 200.0;
      const dW = targetW - origW;

      final template = TemplateParameterDefinition(
        templateId: '45_deg_bend',
        name: '45 Deg Bend',
        category: 'Trunking Fittings',
        productType: 'Bend',
        baselineParameters: {'width': origW, 'height': 50.0, 'flangeWidth': 15.0},
        parameters: const [
          CadParameter(id: 'width', name: 'Width', value: origW),
          CadParameter(id: 'height', name: 'Height', value: 50.0),
          CadParameter(id: 'flangeWidth', name: 'Flange Width', value: 15.0),
        ],
      );

      final scaled = TopologicalZoneMorpher.morph(
        baselineDocument: doc,
        template: template,
        targetParameters: {'width': targetW, 'height': 50.0, 'flangeWidth': 15.0},
      );

      // ── Invariant W1: Outer B1 spine length is preserved (no spurious drawing length expansion) ──
      final origB1 = doc.bends.firstWhere((b) => b.id == 'B1');
      final scaledB1 = scaled.bends.firstWhere((b) => b.id == 'B1');
      final origB1Len = (origB1.p2.x - origB1.p1.x).abs();
      final scaledB1Len = (scaledB1.p2.x - scaledB1.p1.x).abs();
      expect((scaledB1Len - origB1Len).abs(), lessThan(0.5), reason: 'Outer B1 spine length must be fixed (drawing length does not expand)');

      // ── Invariant W2: Port 1 and Port 2 floor edge widths expand by dW ──────
      final origB3 = doc.bends.firstWhere((b) => b.id == 'B3');
      final scaledB3 = scaled.bends.firstWhere((b) => b.id == 'B3');
      final origB3Base = origB3.p1.x < origB3.p2.x ? origB3.p1 : origB3.p2;
      final scaledB3Base = scaledB3.p1.x < scaledB3.p2.x ? scaledB3.p1 : scaledB3.p2;
      final origB1Left = origB1.p1.x < origB1.p2.x ? origB1.p1 : origB1.p2;
      final scaledB1Left = scaledB1.p1.x < scaledB1.p2.x ? scaledB1.p1 : scaledB1.p2;

      final origPort1W = origB3Base.distanceTo(origB1Left);
      final scaledPort1W = scaledB3Base.distanceTo(scaledB1Left);
      expect((scaledPort1W - (origPort1W + dW)).abs(), lessThan(0.5), reason: 'Port 1 mouth width must expand by exactly dW');

      final origB2 = doc.bends.firstWhere((b) => b.id == 'B2');
      final scaledB2 = scaled.bends.firstWhere((b) => b.id == 'B2');
      final origB2Base = origB2.p1.x > origB2.p2.x ? origB2.p1 : origB2.p2;
      final scaledB2Base = scaledB2.p1.x > scaledB2.p2.x ? scaledB2.p1 : scaledB2.p2;
      final origB1Right = origB1.p1.x > origB1.p2.x ? origB1.p1 : origB1.p2;
      final scaledB1Right = scaledB1.p1.x > scaledB1.p2.x ? scaledB1.p1 : scaledB1.p2;

      final origPort2W = origB2Base.distanceTo(origB1Right);
      final scaledPort2W = scaledB2Base.distanceTo(scaledB1Right);
      expect((scaledPort2W - (origPort2W + dW)).abs(), lessThan(0.5), reason: 'Port 2 mouth width must expand by exactly dW');

      // ── Invariant W3: All 8 coupler punches rigid (size unchanged) ────────────
      expect(scaled.punches.length, equals(8));
      for (final p in scaled.punches) {
        expect((p.widthMm - 8.0).abs(), lessThan(1e-3));
        expect((p.lengthMm - 12.0).abs(), lessThan(1e-3));
        expect(p.isCoupler, isTrue);
      }

      // ── Invariant W4: Apex remains on symmetry axis ─────────────────────────
      final origBounds = _computeContourBounds(doc.outerContour);
      final origXCenter = (origBounds.minX + origBounds.maxX) / 2.0;
      final origApexB2 = doc.bends.firstWhere((b) => (b.p1.x - origXCenter).abs() < 5.0 && b.p1.y > 150.0);
      final scaledApexB2 = scaled.bends.firstWhere((b) => b.id == origApexB2.id);
      expect((scaledApexB2.p1.x - origXCenter).abs(), lessThan(2.0), reason: 'Apex x must remain on symmetry axis');

      // ── Invariant W5: 3D fold and port topology preserved ────────────────────
      final foldResult = KinematicFoldEngine.foldDocument(scaled);
      expect(foldResult.polygons.isNotEmpty, isTrue);
      final topo = StructuralTopologyAnalyzer.analyze(scaled);
      expect(topo.detectedPorts.length, equals(2));
      expect(topo.couplerPunches.length, equals(8));
      expect(topo.isHighConfidence, isTrue);
    });

    test('3b. Height invariants: all 3 walls grow in height by dH, apex stationary, slit angle preserved', () async {
      final file = File('assets/dxf_templates/trunking_accessories/45_deg_bend_100x100.dsf');
      final content = await file.readAsString();
      final doc = DsfDocument.fromJson(jsonDecode(content) as Map<String, dynamic>);

      const origH = 50.0;
      const targetH = 100.0;
      const dH = targetH - origH;

      final template = TemplateParameterDefinition(
        templateId: '45_deg_bend',
        name: '45 Deg Bend',
        category: 'Trunking Fittings',
        productType: 'Bend',
        baselineParameters: {'width': 100.0, 'height': origH, 'flangeWidth': 15.0},
        parameters: const [
          CadParameter(id: 'width', name: 'Width', value: 100.0),
          CadParameter(id: 'height', name: 'Height', value: origH),
          CadParameter(id: 'flangeWidth', name: 'Flange Width', value: 15.0),
        ],
      );

      final scaled = TopologicalZoneMorpher.morph(
        baselineDocument: doc,
        template: template,
        targetParameters: {'width': 100.0, 'height': targetH, 'flangeWidth': 15.0},
      );

      // ── Invariant H1: All 8 coupler punches rigid ─────────────────────────────
      expect(scaled.punches.length, equals(8));
      for (final p in scaled.punches) {
        expect((p.widthMm - 8.0).abs(), lessThan(1e-3));
        expect((p.lengthMm - 12.0).abs(), lessThan(1e-3));
      }

      // ── Invariant H2: Outer wall grows down by dH away from B1 ───────────────
      final origB1 = doc.bends.firstWhere((b) => b.id == 'B1');
      final scaledB1 = scaled.bends.firstWhere((b) => b.id == 'B1');
      expect((scaledB1.p1.y - origB1.p1.y).abs(), lessThan(0.5), reason: 'B1 outer wall fold line remains fixed on the floor');

      final origFL1 = doc.bends.firstWhere((b) => b.id == 'FL1');
      final scaledFL1 = scaled.bends.firstWhere((b) => b.id == 'FL1');
      final origOuterWallH = (origB1.p1.y - origFL1.p1.y).abs();
      final scaledOuterWallH = (scaledB1.p1.y - scaledFL1.p1.y).abs();
      expect((scaledOuterWallH - (origOuterWallH + dH)).abs(), lessThan(1.0), reason: 'Outer wall height must increase by dH');

      // ── Invariant H3: Left inner wall grows in height by dH ──────────────────
      final origB3 = doc.bends.firstWhere((b) => b.id == 'B3');
      final scaledB3 = scaled.bends.firstWhere((b) => b.id == 'B3');
      final origFL3 = doc.bends.firstWhere((b) => b.id == 'FL3');
      final scaledFL3 = scaled.bends.firstWhere((b) => b.id == 'FL3');
      // B3 bend line remains stationary on the floor web
      expect(scaledB3.p1.distanceTo(origB3.p1), lessThan(0.5), reason: 'B3 bend line must stay fixed on the floor when height scales');
      // Distance from B3 to FL3 increases by dH
      final origLeftWallH = origB3.p1.distanceTo(origFL3.p1);
      final scaledLeftWallH = scaledB3.p1.distanceTo(scaledFL3.p1);
      expect((scaledLeftWallH - (origLeftWallH + dH)).abs(), lessThan(1.0), reason: 'Left inner wall must grow by dH (not a sitting duck)');

      // ── Invariant H4: Right inner wall grows in height by dH ─────────────────
      final origB2 = doc.bends.firstWhere((b) => b.id == 'B2');
      final scaledB2 = scaled.bends.firstWhere((b) => b.id == 'B2');
      final origFL2 = doc.bends.firstWhere((b) => b.id == 'FL2');
      final scaledFL2 = scaled.bends.firstWhere((b) => b.id == 'FL2');
      // B2 bend line remains stationary on the floor web
      expect(scaledB2.p2.distanceTo(origB2.p2), lessThan(0.5), reason: 'B2 bend line must stay fixed on the floor when height scales');
      final origRightWallH = origB2.p2.distanceTo(origFL2.p2);
      final scaledRightWallH = scaledB2.p2.distanceTo(scaledFL2.p2);
      expect((scaledRightWallH - (origRightWallH + dH)).abs(), lessThan(1.0), reason: 'Right inner wall must grow by dH (not a sitting duck)');

      // ── Invariant H5: Floor apex is invariant to dH (slit angle preserved) ───
      final origApex = origB2.p1;
      final scaledApex = scaledB2.p1;
      expect(scaledApex.distanceTo(origApex), lessThan(0.5), reason: 'Floor apex must not move when height changes; slit angle preserved');

      // ── Invariant H6: 3D fold and port topology preserved ────────────────────
      final foldResult = KinematicFoldEngine.foldDocument(scaled);
      expect(foldResult.polygons.isNotEmpty, isTrue);
      final topo = StructuralTopologyAnalyzer.analyze(scaled);
      expect(topo.detectedPorts.length, equals(2));
      expect(topo.couplerPunches.length, equals(8));
      expect(topo.isHighConfidence, isTrue);
    });

    test('3c. Flange invariants: flange root attached, only tip extends with dFL', () async {
      final file = File('assets/dxf_templates/trunking_accessories/45_deg_bend_100x100.dsf');
      final content = await file.readAsString();
      final doc = DsfDocument.fromJson(jsonDecode(content) as Map<String, dynamic>);

      const origFL = 15.0;
      const targetFL = 25.0;
      const dFL = targetFL - origFL;

      final template = TemplateParameterDefinition(
        templateId: '45_deg_bend',
        name: '45 Deg Bend',
        category: 'Trunking Fittings',
        productType: 'Bend',
        baselineParameters: {'width': 100.0, 'height': 50.0, 'flangeWidth': origFL},
        parameters: const [
          CadParameter(id: 'width', name: 'Width', value: 100.0),
          CadParameter(id: 'height', name: 'Height', value: 50.0),
          CadParameter(id: 'flangeWidth', name: 'Flange Width', value: origFL),
        ],
      );

      final scaled = TopologicalZoneMorpher.morph(
        baselineDocument: doc,
        template: template,
        targetParameters: {'width': 100.0, 'height': 50.0, 'flangeWidth': targetFL},
      );

      // ── Invariant FL1: All coupler punches rigid ───────────────────────────────
      for (final p in scaled.punches) {
        expect((p.widthMm - 8.0).abs(), lessThan(1e-3));
        expect((p.lengthMm - 12.0).abs(), lessThan(1e-3));
      }

      // ── Invariant FL2: FL3 and FL2 flange roots unchanged (wall height unchanged) ─
      final origFL3 = doc.bends.firstWhere((b) => b.id == 'FL3');
      final scaledFL3 = scaled.bends.firstWhere((b) => b.id == 'FL3');
      expect(scaledFL3.p1.distanceTo(origFL3.p1), lessThan(0.5), reason: 'FL3 bend line must not move when only dFL changes');

      final origFL2 = doc.bends.firstWhere((b) => b.id == 'FL2');
      final scaledFL2 = scaled.bends.firstWhere((b) => b.id == 'FL2');
      expect(scaledFL2.p2.distanceTo(origFL2.p2), lessThan(0.5), reason: 'FL2 bend line must not move when only dFL changes');

      // ── Invariant FL3: 3D fold and port topology preserved ───────────────────
      final foldResult = KinematicFoldEngine.foldDocument(scaled);
      expect(foldResult.polygons.isNotEmpty, isTrue);
      final topo = StructuralTopologyAnalyzer.analyze(scaled);
      expect(topo.detectedPorts.length, equals(2));
      expect(topo.isHighConfidence, isTrue);
    });

    test('4. End-to-End: TopologicalZoneMorpher & GeometricConstraintSolver on 45_deg_bend', () async {
      final file = File('assets/dxf_templates/trunking_accessories/45_deg_bend_100x100.dsf');
      final content = await file.readAsString();
      final doc = DsfDocument.fromJson(jsonDecode(content) as Map<String, dynamic>);

      // Create standard template definition for 45_deg_bend
      final template = TemplateParameterDefinition(
        templateId: '45_deg_bend',
        name: '45 Deg Bend Fitting',
        category: 'Trunking Fittings',
        productType: 'Bend',
        baselineParameters: {'width': 100.0, 'height': 50.0, 'flangeWidth': 15.0},
        parameters: const [
          CadParameter(id: 'width', name: 'Width', value: 100.0),
          CadParameter(id: 'height', name: 'Height', value: 50.0),
          CadParameter(id: 'flangeWidth', name: 'Flange Width', value: 15.0),
        ],
      );

      // 1. Morph through TopologicalZoneMorpher
      final morphedDoc = TopologicalZoneMorpher.morph(
        baselineDocument: doc,
        template: template,
        targetParameters: {'width': 160.0, 'height': 75.0, 'flangeWidth': 20.0},
      );

      expect(morphedDoc.punches.length, equals(8));
      for (final p in morphedDoc.punches) {
        expect(p.type, equals(PunchType.obroundSlot));
        expect((p.widthMm - 8.0).abs(), lessThan(1e-3), reason: 'Punch width must be strictly rigid');
        expect((p.lengthMm - 12.0).abs(), lessThan(1e-3), reason: 'Punch length must be strictly rigid');
        expect(p.isCoupler, isTrue);
      }

      // 2. Solve through GeometricConstraintSolver
      final solveResult = GeometricConstraintSolver.solve(document: morphedDoc, parameterOverrides: {'width': 160.0, 'height': 75.0});

      expect(solveResult.success, isTrue);
      final finalDoc = solveResult.updatedDocument;

      // 3. Verify final punches remain rigid
      expect(finalDoc.punches.length, equals(8));
      for (final p in finalDoc.punches) {
        expect((p.widthMm - 8.0).abs(), lessThan(1e-3));
        expect((p.lengthMm - 12.0).abs(), lessThan(1e-3));
      }

      // 4. Verify 3D folding works on final solved document
      final foldResult = KinematicFoldEngine.foldDocument(finalDoc);
      expect(foldResult.polygons.isNotEmpty, isTrue);
      expect(foldResult.boundWidth, greaterThan(0.0));
      expect(foldResult.boundHeight, greaterThan(0.0));

      // 5. Verify StructuralTopologyAnalyzer matches catalog contract
      final topoResult = StructuralTopologyAnalyzer.analyze(finalDoc);
      expect(topoResult.floorFace, isNotNull);
      expect(topoResult.detectedPorts.length, equals(2));
      expect(topoResult.couplerPunches.length, equals(8));
      expect(topoResult.isHighConfidence, isTrue);
    });
  });
}

CadBounds2D _computeContourBounds(List<CadPoint2D> pts) {
  double minX = double.infinity, maxX = -double.infinity;
  double minY = double.infinity, maxY = -double.infinity;
  for (final p in pts) {
    if (p.x < minX) minX = p.x;
    if (p.x > maxX) maxX = p.x;
    if (p.y < minY) minY = p.y;
    if (p.y > maxY) maxY = p.y;
  }
  return CadBounds2D(minX: minX, maxX: maxX, minY: minY, maxY: maxY);
}

class CadBounds2D {
  final double minX, maxX, minY, maxY;
  const CadBounds2D({required this.minX, required this.maxX, required this.minY, required this.maxY});
}
