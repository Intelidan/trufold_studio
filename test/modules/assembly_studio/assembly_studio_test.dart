import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm_math;

import 'package:trufold_studio/assembly_studio/models/assembly_compliance.dart';
import 'package:trufold_studio/assembly_studio/models/assembly_part.dart';
import 'package:trufold_studio/assembly_studio/engine/assembly_raycaster.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/assembly_studio/viewmodels/assembly_studio_viewmodel.dart';
import 'package:trufold_studio/assembly_studio/views/assembly_studio_screen.dart';
import 'package:trufold_studio/assembly_studio/views/widgets/assembly_3d_viewport.dart';
import 'package:trufold_studio/assembly_studio/views/widgets/assembly_inspector_panel.dart';
import 'package:trufold_studio/assembly_studio/views/widgets/assembly_sketchup_toolbar.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/flutter_scene_cad_mesh_builder.dart';

void main() {
  group('AssemblyPart Model Tests', () {
    test('creates straight side rail with editable 20mm flange and coupler holes', () {
      final rail = AssemblyPart(
        id: 'rail_test_1',
        name: 'Straight Rail',
        type: AssemblyPartType.straightRail,
        length: 1000.0,
        height: 100.0,
        flangeWidth: 20.0,
      );

      expect(rail.length, 1000.0);
      expect(rail.height, 100.0);
      expect(rail.flangeWidth, 20.0);

      final mesh = rail.build3DMesh();
      expect(mesh.polygons.isNotEmpty, isTrue);

      // Web face should exist and have coupler holes
      final webPoly = mesh.polygons.firstWhere((p) => p.faceId.contains('_web'));
      expect(webPoly, isNotNull);
      expect(webPoly.holes.isNotEmpty, isTrue);
    });

    test('creates bent side rail with auto-cut V-notch on flanges', () {
      final bentRail = AssemblyPart(
        id: 'bent_rail_1',
        name: 'Bent Rail 3 Segments',
        type: AssemblyPartType.bentRail,
        height: 100.0,
        flangeWidth: 20.0,
        segments: [
          RailSegmentDefinition(id: 's1', length: 300.0, bendAngleDeg: 0.0),
          RailSegmentDefinition(id: 's2', length: 250.0, bendAngleDeg: 45.0, hasFlangeVNotch: true),
          RailSegmentDefinition(id: 's3', length: 300.0, bendAngleDeg: 0.0, hasFlangeVNotch: true),
        ],
      );

      expect(bentRail.segments.length, 3);
      expect(bentRail.segments[1].hasFlangeVNotch, isTrue);

      final mesh = bentRail.build3DMesh();
      expect(mesh.polygons.isNotEmpty, isTrue);

      // Top flange segments should exist
      final topFlangePolys = mesh.polygons.where((p) => p.faceId.contains('_flange_top')).toList();
      expect(topFlangePolys.length, 3);
    });

    test('creates slotted C-channel rung with obround slots', () {
      final rung = AssemblyPart(
        id: 'rung_test_1',
        name: 'Slotted Rung',
        type: AssemblyPartType.rung,
        length: 600.0,
        height: 20.0,
        flangeWidth: 20.0,
      );

      final mesh = rung.build3DMesh();
      expect(mesh.polygons.isNotEmpty, isTrue);

      final topWeb = mesh.polygons.firstWhere((p) => p.faceId.contains('_top_web'));
      expect(topWeb.holes.isNotEmpty, isTrue); // Cable tie slots
    });
  });

  group('AssemblyStudioViewModel Tests', () {
    test('standard ladder demo spawns rails and rungs with welds', () {
      final vm = AssemblyStudioViewModel();
      expect(vm.doc.parts.isNotEmpty, isTrue);
      expect(vm.doc.welds.isNotEmpty, isTrue);

      final leftRail = vm.doc.parts.firstWhere((p) => p.id == 'rail_left');
      expect(leftRail.flangeWidth, 20.0);
      expect(leftRail.weldedToPartIds.isNotEmpty, isTrue);
    });

    test('direct dimensions editing and 20mm flange update', () {
      final vm = AssemblyStudioViewModel();
      vm.selectPart('rail_left');

      vm.updateSelectedLength(1500.0);
      expect(vm.selectedPart!.length, 1500.0);

      vm.updateSelectedFlangeWidth(25.0);
      expect(vm.selectedPart!.flangeWidth, 25.0);

      vm.updateSelectedHeight(125.0);
      expect(vm.selectedPart!.height, 125.0);
    });

    test('micro adjustments nudge position and rotation', () {
      final vm = AssemblyStudioViewModel();
      vm.selectPart('rail_left');
      final initPos = vm.selectedPart!.position;

      vm.nudgeSelectedPosition(10.0, 5.0, -2.0);
      expect(vm.selectedPart!.position.x, initPos.x + 10.0);
      expect(vm.selectedPart!.position.y, initPos.y + 5.0);
      expect(vm.selectedPart!.position.z, initPos.z - 2.0);

      vm.nudgeSelectedRotation(0.0, 0.0, 90.0);
      expect(vm.selectedPart!.rotationDeg.z, 90.0);
    });

    test('welding and breaking welds between parts', () {
      final vm = AssemblyStudioViewModel();
      vm.addStraightRail(length: 600.0);
      final newRailId = vm.selectedPart!.id;

      vm.weldParts(newRailId, 'rail_left');
      final activeWelds = vm.doc.welds.where((w) => w.partAId == newRailId && w.partBId == 'rail_left').toList();
      expect(activeWelds.isNotEmpty, isTrue);

      // Break weld
      vm.breakWeld(activeWelds.first.id);
      final afterBreak = vm.doc.welds.where((w) => w.id == activeWelds.first.id).toList();
      expect(afterBreak.isEmpty, isTrue);
    });

    test('WYSIWYG Face Sketch mode adds features and updates 3D model', () {
      final vm = AssemblyStudioViewModel();
      vm.selectPart('rail_left');

      vm.enterSketchMode(faceId: 'rail_left_web');
      expect(vm.isSketchMode, isTrue);
      expect(vm.isOrthoProjection, isTrue);

      final initialSketchCount = vm.selectedPart!.sketches.length;

      vm.addSketchFeature(
        featureType: 'circle_hole',
        localCenter: const CadPoint2D(150.0, 50.0),
        widthMm: 12.0,
        heightMm: 12.0,
      );

      final rail = vm.doc.parts.firstWhere((p) => p.id == 'rail_left');
      expect(rail.sketches.length, initialSketchCount + 1);
      expect(rail.sketches.last.featureType, 'circle_hole');

      // 3D mesh should update with the new hole
      final mesh = vm.assemblyMesh;
      final railWeb = mesh.polygons.firstWhere((p) => p.faceId == 'rail_left_web');
      expect(railWeb.holes.isNotEmpty, isTrue);

      vm.exitSketchMode();
      expect(vm.isSketchMode, isFalse);
    });

    test('Direct 3D sketch with "S" key focuses part, locks 3D movement, and unlocks on finish', () {
      final vm = AssemblyStudioViewModel();
      vm.selectPart('rail_left');

      // User presses 'S'
      vm.focusPartAndEnterSketch('rail_left');
      expect(vm.isSketchMode, isTrue);
      expect(vm.is3DMovementLocked, isTrue);
      expect(vm.sketchPartId, 'rail_left');
      expect(vm.isOrthoProjection, isTrue);

      // Finishes sketching (Enter / Esc / Green checkmark)
      vm.finishSketch();
      expect(vm.isSketchMode, isFalse);
      expect(vm.is3DMovementLocked, isFalse);
    });

    test('Punched rung slot becomes entity and C-channel links, snaps, and flips upside down', () {
      final vm = AssemblyStudioViewModel();
      final rail = vm.doc.parts.firstWhere((p) => p.id == 'rail_left');

      // 1. Punch a new rung slot entity at calculated distance 750mm
      vm.punchRungSlot(railId: rail.id, distanceX: 750.0);
      final punchedSlot = rail.sketches.firstWhere((s) => s.distanceAlongRailMm == 750.0);
      expect(punchedSlot.isRungSlotEntity, isTrue);
      expect(punchedSlot.widthMm, 40.5); // slot fits 40mm rung flange
      expect(punchedSlot.heightMm, 20.5); // slot fits 20mm rung height

      // 2. Add an unlinked C-channel rung
      vm.addRung(length: 450.0);
      final newRungId = vm.selectedPart!.id;

      // 3. Link C-channel rung to the punched slot entity (Pass-Through style)
      vm.linkRungToSlot(
        rungPartId: newRungId,
        slotEntityId: punchedSlot.id,
        mateStyle: 'passThrough',
      );

      final matedRung = vm.doc.parts.firstWhere((p) => p.id == newRungId);
      expect(matedRung.parentPartId, rail.id);
      expect(matedRung.matedSlotEntityId, punchedSlot.id);
      expect(matedRung.jointType, AssemblyJointType.slotMate);
      expect(matedRung.position.x, rail.position.x + 750.0);
      expect(matedRung.position.y, rail.position.y - 10.0); // Pass-through protrudes -10mm
      expect(matedRung.rotationDeg.z, 90.0); // Transverse yaw 90°

      // 4. Flip rung upside down 180°
      expect(matedRung.isRungUpsideDown, isFalse);
      vm.toggleRungUpsideDown(newRungId);
      expect(matedRung.isRungUpsideDown, isTrue);
      expect(matedRung.rotationDeg.x, 180.0); // Roll 180° inverted

      // 5. Switch to Direct-Inside mate style
      vm.setRungJointStyle(newRungId, 'directInside');
      expect(matedRung.position.y, rail.position.y); // Flush at 0.0mm
    });

    test('Assembly Set rigid translation propagates from parent rail to mated rungs', () {
      final vm = AssemblyStudioViewModel();
      vm.selectPart('rail_left');
      final parentRail = vm.selectedPart!;

      final childRung = vm.doc.parts.firstWhere((p) => p.parentPartId == 'rail_left');
      final initialChildX = childRung.position.x;
      final initialChildY = childRung.position.y;
      final initialChildZ = childRung.position.z;

      // Nudge parent rail by dx=50, dy=20, dz=15
      vm.nudgeSelectedPosition(50.0, 20.0, 15.0);

      expect(parentRail.position.x, 50.0);
      expect(childRung.position.x, initialChildX + 50.0);
      expect(childRung.position.y, initialChildY + 20.0);
      expect(childRung.position.z, initialChildZ + 15.0);
    });

    test('Joint modes (welded, fused, hinged) and separation', () {
      final vm = AssemblyStudioViewModel();
      vm.addStraightRail(length: 500.0);
      final partA = vm.selectedPart!.id;
      vm.addStraightRail(length: 500.0);
      final partB = vm.selectedPart!.id;

      // Join hinged
      vm.joinParts(partA, partB, AssemblyJointType.hinged);
      final joint = vm.doc.welds.firstWhere((w) => w.partAId == partA && w.partBId == partB);
      expect(joint.jointType, AssemblyJointType.hinged);

      // Separate
      vm.separateParts(partA, partB);
      expect(vm.doc.welds.any((w) => w.partAId == partA && w.partBId == partB), isFalse);
    });

    test('Spawning structural parts: channel, angle, rod, bar, and i-beam with 3D meshes', () {
      final vm = AssemblyStudioViewModel();
      vm.clearAll();

      // C-Channel
      vm.addChannel(length: 800.0, webHeight: 75.0, flangeWidth: 35.0);
      final channel = vm.selectedPart!;
      expect(channel.type, AssemblyPartType.channel);
      expect(channel.build3DMesh().polygons.isNotEmpty, isTrue);

      // L-Angle
      vm.addAngle(length: 600.0, legA: 50.0, legB: 50.0);
      final angle = vm.selectedPart!;
      expect(angle.type, AssemblyPartType.angle);
      expect(angle.build3DMesh().polygons.isNotEmpty, isTrue);

      // Round Rod
      vm.addRod(length: 500.0, diameter: 20.0);
      final rod = vm.selectedPart!;
      expect(rod.type, AssemblyPartType.rod);
      expect(rod.build3DMesh().polygons.isNotEmpty, isTrue);

      // Flat Bar
      vm.addFlatBar(length: 400.0, width: 40.0, thickness: 6.0);
      final bar = vm.selectedPart!;
      expect(bar.type, AssemblyPartType.bar);
      expect(bar.build3DMesh().polygons.isNotEmpty, isTrue);

      // I-Beam
      vm.addIBeam(length: 1200.0, height: 100.0, flangeWidth: 60.0);
      final iBeam = vm.selectedPart!;
      expect(iBeam.type, AssemblyPartType.iBeam);
      expect(iBeam.build3DMesh().polygons.isNotEmpty, isTrue);

      expect(vm.doc.parts.length, 5);
    });

    test('SketchUp tool modes (select, move, rotate) and shortcuts', () {
      final vm = AssemblyStudioViewModel();
      expect(vm.activeToolMode, SketchUpToolMode.select);

      // Switch to Move (M)
      vm.setToolMode(SketchUpToolMode.move);
      expect(vm.activeToolMode, SketchUpToolMode.move);
      expect(vm.gizmoMode, GizmoMode.translate);

      // Switch to Rotate (R)
      vm.setToolMode(SketchUpToolMode.rotate);
      expect(vm.activeToolMode, SketchUpToolMode.rotate);
      expect(vm.gizmoMode, GizmoMode.rotate);

      // Switch to Select (V/Space)
      vm.setToolMode(SketchUpToolMode.select);
      expect(vm.activeToolMode, SketchUpToolMode.select);
    });

    test('Moving sketched entities (holes, slots) freely on part face', () {
      final vm = AssemblyStudioViewModel();
      vm.selectPart('rail_left');
      final rail = vm.selectedPart!;

      // Add circle hole at (100, 30)
      vm.addSketchFeature(
        featureType: 'circle_hole',
        localCenter: const CadPoint2D(100.0, 30.0),
        widthMm: 12.0,
        heightMm: 12.0,
      );
      final hole = rail.sketches.last;
      expect(hole.localCenter.x, 100.0);
      expect(hole.localCenter.y, 30.0);

      // Move hole by (+50, +10) freely
      vm.moveSketchFeature(rail.id, hole.id, 50.0, 10.0);
      expect(hole.localCenter.x, 150.0);
      expect(hole.localCenter.y, 40.0);
    });

    test('Moving bend lines and entities freely with setSketchFeaturePosition', () {
      final vm = AssemblyStudioViewModel();
      vm.selectPart('rail_left');
      final rail = vm.selectedPart!;

      // Add a bend line at X = 250mm
      vm.addSketchFeature(
        featureType: 'bend_line',
        localCenter: const CadPoint2D(250.0, 50.0),
        widthMm: 2.0,
        heightMm: 100.0,
      );
      final bend = rail.sketches.last;
      expect(bend.featureType, 'bend_line');
      expect(bend.localCenter.x, 250.0);

      // Select sketch feature
      vm.selectSketchFeature(bend.id);
      expect(vm.selectedSketchFeatureId, bend.id);

      // Move bend line freely to X = 420mm, Y = 60mm
      vm.setSketchFeaturePosition(rail.id, bend.id, 420.0, 60.0);
      expect(bend.localCenter.x, 420.0);
      expect(bend.localCenter.y, 60.0);

      // Verify bend line is built into 3D mesh
      final mesh = rail.build3DMesh();
      expect(mesh.polygons.any((p) => p.faceId.contains('bend')), isTrue);
    });

    test('Structural sections (channel, angle, i-beam) render holes and bend lines in 3D', () {
      final vm = AssemblyStudioViewModel();
      vm.doc.parts.clear();

      // Add C-channel
      vm.addChannel(length: 800.0, webHeight: 80.0, flangeWidth: 40.0);
      final channel = vm.selectedPart!;
      vm.addSketchFeature(
        featureType: 'circle_hole',
        localCenter: const CadPoint2D(120.0, 40.0),
        widthMm: 14.0,
        heightMm: 14.0,
      );
      vm.addSketchFeature(
        featureType: 'bend_line',
        localCenter: const CadPoint2D(400.0, 40.0),
        widthMm: 2.0,
        heightMm: 80.0,
      );

      final chMesh = channel.build3DMesh();
      final webPoly = chMesh.polygons.firstWhere((p) => p.faceId.contains('web'));
      expect(webPoly.holes.isNotEmpty, isTrue);
      expect(chMesh.polygons.any((p) => p.faceId.contains('bend')), isTrue);

      // Add I-beam
      vm.addIBeam(length: 1000.0, height: 120.0, flangeWidth: 70.0);
      final iBeam = vm.selectedPart!;
      vm.addSketchFeature(
        featureType: 'obround_slot',
        localCenter: const CadPoint2D(200.0, 60.0),
        widthMm: 30.0,
        heightMm: 15.0,
      );
      final ibMesh = iBeam.build3DMesh();
      final ibWeb = ibMesh.polygons.firstWhere((p) => p.faceId.contains('web'));
      expect(ibWeb.holes.isNotEmpty, isTrue);
    });

    test('Undo and Redo stack works correctly', () {
      final vm = AssemblyStudioViewModel();
      vm.selectPart('rail_left');

      final oldLength = vm.selectedPart!.length;
      vm.updateSelectedLength(2000.0);
      expect(vm.selectedPart!.length, 2000.0);
      expect(vm.canUndo, isTrue);

      vm.undo();
      expect(vm.selectedPart!.length, oldLength);
      expect(vm.canRedo, isTrue);

      vm.redo();
      expect(vm.selectedPart!.length, 2000.0);
    });

    test('Requirement 2: Part selection does NOT add immediately, waits for click-to-place or drag drop', () {
      final vm = AssemblyStudioViewModel();
      final initialCount = vm.doc.parts.length;

      // User selects a part in Common Parts palette
      vm.setPendingPlacement(const PendingPartPlacement(
        type: AssemblyPartType.channel,
        name: '75x35mm C-Channel',
        length: 1500.0,
        height: 75.0,
        flangeWidth: 35.0,
        thickness: 3.0,
      ));

      // Part must NOT be added immediately to the drawing board!
      expect(vm.doc.parts.length, initialCount);
      expect(vm.pendingPlacement, isNotNull);
      expect(vm.pendingPlacement!.type, AssemblyPartType.channel);

      // User can cancel placement
      vm.cancelPendingPlacement();
      expect(vm.pendingPlacement, isNull);
      expect(vm.doc.parts.length, initialCount);

      // Re-set and place at clicked 3D point on the drawing board
      vm.setPendingPlacement(const PendingPartPlacement(
        type: AssemblyPartType.channel,
        name: '75x35mm C-Channel',
        length: 1500.0,
        height: 75.0,
        flangeWidth: 35.0,
        thickness: 3.0,
      ));

      final placedPart = vm.placePendingPartAt(const CadPoint3D(350.0, 0.0, 500.0));
      expect(placedPart, isNotNull);
      expect(placedPart!.position, const CadPoint3D(350.0, 0.0, 500.0));
      expect(vm.doc.parts.length, initialCount + 1);
      expect(vm.doc.selectedPartId, placedPart.id);
      expect(vm.pendingPlacement, isNull); // Cleared after placement
    });

    test('Requirement 3: Whole-part group selection when clicking any polygon/face', () {
      final vm = AssemblyStudioViewModel();
      expect(vm.doc.parts.isNotEmpty, isTrue);

      final rail = vm.doc.parts.first;
      // User clicks a sub-face belonging to this part:
      vm.selectFace('${rail.id}_web');

      // Part must select as a whole group, not individual faces
      expect(vm.doc.selectedPartId, rail.id);
      expect(vm.doc.selectedFaceId, isNull);
    });

    test('Requirement 4: Part click, hold, and direct dragging across the drawing board', () {
      final vm = AssemblyStudioViewModel();
      final rail = vm.doc.parts.first;
      final startPos = rail.position;

      // Dragging part to a new position across the drawing board:
      // Pre-drag state is saved for undo
      vm.recordHistory();
      rail.position = CadPoint3D(startPos.x + 150.0, startPos.y, startPos.z + 250.0);
      vm.notifyDocChanged();

      expect(rail.position.x, startPos.x + 150.0);
      expect(rail.position.z, startPos.z + 250.0);

      // Undo brings it right back
      expect(vm.canUndo, isTrue);
      vm.undo();
      expect(vm.doc.parts.first.position.x, startPos.x);
      expect(vm.doc.parts.first.position.z, startPos.z);
    });

    test('Requirement 6: Camera panning is allowed in sketch mode', () {
      final vm = AssemblyStudioViewModel();
      vm.focusPartAndEnterSketch('rail_left');
      expect(vm.isSketchMode, isTrue);
      expect(vm.is3DMovementLocked, isTrue);

      // Panning pan offset can change freely during sketch mode
      final startPan = vm.pan;
      vm.pan = Offset(startPan.dx + 45.0, startPan.dy - 30.0);
      expect(vm.pan.dx, startPan.dx + 45.0);
      expect(vm.pan.dy, startPan.dy - 30.0);
    });

    test('SketchUp Navigation: Arrow-key axis locking (Red X, Green Y, Blue Z)', () {
      final vm = AssemblyStudioViewModel();
      expect(vm.lockedAxis, GizmoAxis.none);

      // Right arrow -> Red Axis (X)
      vm.setLockedAxis(GizmoAxis.x);
      expect(vm.lockedAxis, GizmoAxis.x);

      // Left arrow -> Green Axis (Y)
      vm.setLockedAxis(GizmoAxis.y);
      expect(vm.lockedAxis, GizmoAxis.y);

      // Up arrow -> Blue Axis (Z)
      vm.setLockedAxis(GizmoAxis.z);
      expect(vm.lockedAxis, GizmoAxis.z);

      // Down arrow -> Unlock axis
      vm.clearLockedAxis();
      expect(vm.lockedAxis, GizmoAxis.none);

      // Toggle behavior
      vm.toggleLockedAxis(GizmoAxis.x);
      expect(vm.lockedAxis, GizmoAxis.x);
      vm.toggleLockedAxis(GizmoAxis.x);
      expect(vm.lockedAxis, GizmoAxis.none);
    });

    test('SketchUp Protractor: Snaps rotation angles to 15-degree increments', () {
      final vm = AssemblyStudioViewModel();
      expect(vm.protractorSnapDeg, 15.0);

      // Exact snap points
      expect(vm.snapRotationAngle(0.0), 0.0);
      expect(vm.snapRotationAngle(14.0), 15.0);
      expect(vm.snapRotationAngle(16.0), 15.0);
      expect(vm.snapRotationAngle(44.0), 45.0);
      expect(vm.snapRotationAngle(89.0), 90.0);
      expect(vm.snapRotationAngle(178.0), 180.0);
    });

    test('Multi-Part Selection: Shift/Ctrl click toggles and manages multi-selection set', () {
      final vm = AssemblyStudioViewModel();
      expect(vm.doc.parts.length, greaterThanOrEqualTo(2));
      final p1 = vm.doc.parts[0];
      final p2 = vm.doc.parts[1];

      // Single selection
      vm.selectPart(p1.id);
      expect(vm.selectedPartIds, {p1.id});
      expect(vm.selectedParts.length, 1);

      // Multi-selection with Shift/Ctrl
      vm.togglePartSelection(p2.id);
      expect(vm.selectedPartIds, {p1.id, p2.id});
      expect(vm.selectedParts.length, 2);

      // Clicking p1 again with multiSelect removes it
      vm.selectPart(p1.id, multiSelect: true);
      expect(vm.selectedPartIds, {p2.id});

      // Select all
      vm.selectAllParts();
      expect(vm.selectedPartIds.length, vm.doc.parts.length);

      // Clear selection
      vm.clearSelection();
      expect(vm.selectedPartIds.isEmpty, isTrue);
      expect(vm.selectedPart, isNull);
    });

    test('Advanced Weld/Link: Automatically welds multiple selected parts at touching contact points', () {
      final vm = AssemblyStudioViewModel();
      vm.doc.parts.clear();
      vm.doc.welds.clear();

      // Add two touching parts: rail at (0,0,0) and rung resting at (0, 0, 50)
      vm.addStraightRail(length: 1000.0, height: 100.0, flangeWidth: 20.0, position: const CadPoint3D(0.0, 0.0, 0.0));
      vm.addRung(length: 500.0, position: const CadPoint3D(0.0, 0.0, 20.0));
      expect(vm.doc.parts.length, 2);

      // Select both parts
      vm.selectAllParts();
      expect(vm.selectedParts.length, 2);

      // Weld at contact points
      final weldsCreated = vm.weldSelectedPartsAtContactPoints();
      expect(weldsCreated, 1);
      expect(vm.doc.welds.length, 1);
      final weld = vm.doc.welds.first;
      expect(weld.partAId, vm.doc.parts[0].id);
      expect(weld.partBId, vm.doc.parts[1].id);
      expect(weld.weldPoint, isNotNull);
    });

    test('Clickable Weld Joints in 3D: Select weld bead directly and break bond', () {
      final vm = AssemblyStudioViewModel();
      expect(vm.doc.welds.isNotEmpty, isTrue);

      final firstWeld = vm.doc.welds.first;
      // In 3D viewport, user clicks directly on the weld bead (faceId starts with 'weld_')
      vm.selectFace('weld_${firstWeld.id}');

      expect(vm.selectedWeldId, firstWeld.id);
      expect(vm.selectedWeld, isNotNull);
      expect(vm.selectedWeld!.id, firstWeld.id);

      // User breaks bond / deletes weld
      vm.deleteSelectedWeld();
      expect(vm.selectedWeldId, isNull);
      expect(vm.doc.welds.any((w) => w.id == firstWeld.id), isFalse);
    });

    test('Unified Tree Hierarchy: Grouped and connected parts appear under one tree node', () {
      final vm = AssemblyStudioViewModel();
      vm.loadStandardLadderDemo();

      // All ladder rungs and rails are welded together, so they form one connected tree group
      final groups = vm.getAssemblyHierarchyGroups();
      expect(groups.isNotEmpty, isTrue);

      final connectedGroup = groups.firstWhere((g) => g.isConnectedAssembly);
      expect(connectedGroup.isConnectedAssembly, isTrue);
      expect(connectedGroup.parts.length, greaterThanOrEqualTo(5));
      expect(connectedGroup.welds.length, greaterThanOrEqualTo(4));

      // Add a loose, independent part not welded to anything
      vm.addStraightRail(length: 500.0, height: 80.0, flangeWidth: 20.0, position: const CadPoint3D(500.0, 500.0, 0.0));
      final updatedGroups = vm.getAssemblyHierarchyGroups();
      final looseGroup = updatedGroups.firstWhere((g) => !g.isConnectedAssembly);
      expect(looseGroup.parts.isNotEmpty, isTrue);
    });

    test('3D Part Visibility: Toggling visibility updates 3D mesh generation', () {
      final vm = AssemblyStudioViewModel();
      expect(vm.doc.parts.isNotEmpty, isTrue);
      final firstPart = vm.doc.parts.first;
      expect(firstPart.isVisible, isTrue);

      final fullMesh = vm.assemblyMesh;
      final fullPolyCount = fullMesh.polygons.length;
      expect(fullPolyCount, greaterThan(0));

      // Hide the first part from the outliner tree
      vm.togglePartVisibility(firstPart.id);
      expect(firstPart.isVisible, isFalse);

      final meshWithHiddenPart = vm.assemblyMesh;
      expect(meshWithHiddenPart.polygons.length, lessThan(fullPolyCount));

      // Show it again
      vm.togglePartVisibility(firstPart.id);
      expect(firstPart.isVisible, isTrue);
      expect(vm.assemblyMesh.polygons.length, fullPolyCount);
    });

    test('GameStudio Helpers: selectPartGroup, updateSelectedWeldSize, and breakBond', () {
      final vm = AssemblyStudioViewModel();
      vm.loadStandardLadderDemo();

      final firstGroup = vm.getAssemblyHierarchyGroups().first;
      vm.selectPartGroup(firstGroup.parts.map((p) => p.id).toList());
      expect(vm.selectedPartIds.length, firstGroup.parts.length);

      // Select weld and update bead size
      final firstWeld = vm.doc.welds.first;
      vm.selectWeld(firstWeld.id);
      vm.updateSelectedWeldSize(12.0);
      expect(vm.selectedWeld!.weldSizeMm, 12.0);

      // Break bond
      final partAId = firstWeld.partAId;
      final partBId = firstWeld.partBId;
      vm.breakBond(partAId, partBId);
      expect(vm.doc.welds.any((w) => w.id == firstWeld.id), isFalse);
    });

    test('Bug 1 Fix: Bent rail top flange vertices are all planar at Z = H with no diagonal clipping', () {
      final rail = AssemblyPart(
        id: 'bent_rail_bug_check',
        name: 'Bent Rail Check',
        type: AssemblyPartType.bentRail,
        height: 100.0,
        flangeWidth: 20.0,
        segments: [
          RailSegmentDefinition(id: 's1', length: 300.0, bendAngleDeg: 0.0),
          RailSegmentDefinition(id: 's2', length: 250.0, bendAngleDeg: 45.0, hasFlangeVNotch: true),
        ],
      );

      final mesh = rail.build3DMesh();
      final topFlangePolys = mesh.polygons.where((p) => p.faceId.contains('flange_top')).toList();
      expect(topFlangePolys.isNotEmpty, isTrue);

      for (final poly in topFlangePolys) {
        // Every single vertex in top flange MUST have Z = H (100.0), never 0.0!
        for (final v in poly.vertices) {
          expect(v.z, closeTo(100.0, 1e-4), reason: 'Top flange vertex had invalid Z: ${v.z}');
        }
      }

      // Check dynamic bounds calculation in document
      final vm = AssemblyStudioViewModel();
      vm.doc.parts.clear();
      vm.doc.parts.add(rail);
      final docMesh = vm.assemblyMesh;
      expect(docMesh.boundWidth, greaterThan(0.0));
      expect(docMesh.boundHeight, closeTo(100.0, 5.0));
    });

    test('Improvements 1 & 2: Ctrl+Click addToSelection, Shift+Click removeFromSelection, Virtual Grouping vs Welding', () {
      final vm = AssemblyStudioViewModel();
      vm.loadStandardLadderDemo();
      expect(vm.doc.parts.length, greaterThanOrEqualTo(3));

      final p1 = vm.doc.parts[0];
      final p2 = vm.doc.parts[1];
      final p3 = vm.doc.parts[2];

      // 1. Initial selection
      vm.selectPart(p1.id);
      expect(vm.selectedPartIds, {p1.id});

      // 2. Ctrl+Click: Add p2 and p3 to selection
      vm.addToSelection(p2.id);
      expect(vm.selectedPartIds, {p1.id, p2.id});

      vm.addToSelection(p3.id);
      expect(vm.selectedPartIds, {p1.id, p2.id, p3.id});

      // 3. Shift+Click: Remove p2 from selection
      vm.removeFromSelection(p2.id);
      expect(vm.selectedPartIds, {p1.id, p3.id});

      // 4. Virtual Grouping: group p1 and p3
      expect(vm.canGroupSelectedParts, isTrue);
      final initialP1Pos = p1.position;
      final initialP3Pos = p3.position;

      final grpId = vm.groupSelectedParts(name: 'Main Frame Group');
      expect(grpId, isNotNull);
      expect(p1.groupId, grpId);
      expect(p3.groupId, grpId);
      expect(p1.groupName, 'Main Frame Group');
      expect(p3.groupName, 'Main Frame Group');

      // Grouping does NOT weld them physically (no new welds added between them)
      expect(p1.position, initialP1Pos);
      expect(p3.position, initialP3Pos);

      // 5. Selecting any member selects the entire virtual group
      vm.clearSelection();
      vm.selectPart(p1.id);
      expect(vm.selectedPartIds, {p1.id, p3.id});

      // 6. Moving a grouped member moves all group members rigidly together!
      vm.updatePartPosition(p1.id, CadPoint3D(initialP1Pos.x + 50.0, initialP1Pos.y + 20.0, initialP1Pos.z + 10.0));
      expect(p1.position.x, initialP1Pos.x + 50.0);
      expect(p1.position.y, initialP1Pos.y + 20.0);
      expect(p1.position.z, initialP1Pos.z + 10.0);

      expect(p3.position.x, initialP3Pos.x + 50.0);
      expect(p3.position.y, initialP3Pos.y + 20.0);
      expect(p3.position.z, initialP3Pos.z + 10.0);

      // 7. Hierarchy Tree shows the virtual group under one unified node
      final hierarchy = vm.getAssemblyHierarchyGroups();
      final virtualNode = hierarchy.where((g) => g.id == grpId).firstOrNull;
      expect(virtualNode, isNotNull);
      expect(virtualNode!.name, 'Main Frame Group');
      expect(virtualNode.parts.length, 2);

      // 8. Ungrouping removes virtual group binding
      expect(vm.canUngroupSelectedParts, isTrue);
      vm.ungroupSelectedParts();
      expect(p1.groupId, isNull);
      expect(p3.groupId, isNull);
      expect(p1.groupName, isNull);
      expect(p3.groupName, isNull);
      expect(vm.canUngroupSelectedParts, isFalse);
    });

    testWidgets('Improvement 3: SketchUp Vertical Toolbar renders all tools matching SS2', (tester) async {
      final vm = AssemblyStudioViewModel();
      bool zoomExtentsClicked = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AssemblySketchupToolbar(
              viewModel: vm,
              onZoomExtents: () {
                zoomExtentsClicked = true;
              },
            ),
          ),
        ),
      );

      // Verify toolbar exists
      expect(find.byType(AssemblySketchupToolbar), findsOneWidget);

      // Verify tool buttons: Tooltips matching SS2 tools
      expect(find.byTooltip('Select (Space / V)'), findsOneWidget);
      expect(find.byTooltip('Materials & Finishes (B)'), findsOneWidget);
      expect(find.byTooltip('Line / Pencil (L)'), findsOneWidget);
      expect(find.byTooltip('Rectangle (Rect Cut)'), findsOneWidget);
      expect(find.byTooltip('Circle / Hole (C)'), findsOneWidget);
      expect(find.byTooltip('2-Point Arc (A)'), findsOneWidget);
      expect(find.byTooltip('Punched Rung Slot / Spline'), findsOneWidget);
      expect(find.byTooltip('Move (M) • Lock axis with arrow keys'), findsOneWidget);
      expect(find.byTooltip('Rotate (R / Q) • 15° Protractor Snap'), findsOneWidget);
      expect(find.byTooltip('Auto-Span Bridge (B) • Connect stiles with rungs & welds'), findsOneWidget);
      expect(find.byTooltip('Fillet Weld (W) • Drag draft line across seam to weld'), findsOneWidget);
      expect(find.byTooltip('Magnetic Snap & Joint (J) • Place snap spot & attract parts'), findsOneWidget);
      expect(find.byTooltip('Scale / Dimensions (S)'), findsOneWidget);
      expect(find.byTooltip('Tape Measure / Dimension (D)'), findsOneWidget);
      expect(find.byTooltip('Protractor (Angle Guide)'), findsOneWidget);
      expect(find.byTooltip('Zoom / Orbit Camera (Z)'), findsOneWidget);
      expect(find.byTooltip('Zoom to Fit / Extents (F)'), findsOneWidget);

      // Test tapping Zoom Extents
      await tester.tap(find.byTooltip('Zoom to Fit / Extents (F)'));
      expect(zoomExtentsClicked, isTrue);

      // Test tapping Move tool
      await tester.tap(find.byTooltip('Move (M) • Lock axis with arrow keys'));
      expect(vm.activeToolMode, SketchUpToolMode.move);

      // Test tapping Rotate tool
      await tester.tap(find.byTooltip('Rotate (R / Q) • 15° Protractor Snap'));
      expect(vm.activeToolMode, SketchUpToolMode.rotate);

      // Test tapping Select tool
      await tester.tap(find.byTooltip('Select (Space / V)'));
      expect(vm.activeToolMode, SketchUpToolMode.select);
    });

    testWidgets('Virtual Grouping Dialog in Viewport: prompts for name and groups parts', (tester) async {
      final vm = AssemblyStudioViewModel();
      vm.loadStandardLadderDemo();
      expect(vm.doc.parts.length, greaterThanOrEqualTo(2));

      // Select two parts
      vm.selectPart(vm.doc.parts[0].id);
      vm.addToSelection(vm.doc.parts[1].id);
      expect(vm.canGroupSelectedParts, isTrue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Assembly3DViewport(viewModel: vm),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the Group (Ctrl+G) button on the floating banner
      final groupButton = find.text('Group (Ctrl+G)');
      expect(groupButton, findsOneWidget);

      await tester.tap(groupButton);
      await tester.pumpAndSettle();

      // Dialog should appear with 'Create Virtual Group'
      expect(find.text('Create Virtual Group'), findsOneWidget);
      expect(find.text('Create Group'), findsOneWidget);

      // Enter a custom name
      await tester.enterText(find.byType(TextField).last, 'Test Frame Subassembly');
      await tester.tap(find.text('Create Group'));
      await tester.pumpAndSettle();

      // Verify parts are grouped with the custom name
      expect(vm.doc.parts[0].groupName, 'Test Frame Subassembly');
      expect(vm.doc.parts[1].groupName, 'Test Frame Subassembly');
      expect(vm.doc.parts[0].groupId, isNotNull);
      expect(vm.doc.parts[0].groupId, vm.doc.parts[1].groupId);
    });

    testWidgets('Rung Selection on Mouse Click: tapping on rungs selects them reliably', (tester) async {
      final vm = AssemblyStudioViewModel();
      vm.loadStandardLadderDemo();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 800,
              child: Assembly3DViewport(viewModel: vm),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();


      // 1. Tapping empty canvas on the left ('O' in user screenshot) never selects any rung
      await tester.tapAt(const Offset(150.0, 400.0));
      await tester.pumpAndSettle();
      expect(vm.doc.selectedPartId, isNull, reason: 'Clicking empty canvas on the left must NOT select any rung');

      // 2. Tapping directly on rung_2 in the 3D viewport selects it reliably
      final actualRung2ScreenPos = const Offset(366.9, 287.5);
      await tester.tapAt(actualRung2ScreenPos);
      await tester.pumpAndSettle();
      expect(vm.doc.selectedPartId, equals('rung_2'), reason: 'Clicking directly on rung_2 must select rung_2');

      // 3. Tapping back on empty canvas deselects without proximity stealing
      await tester.tapAt(const Offset(150.0, 400.0));
      await tester.pumpAndSettle();
      expect(vm.doc.selectedPartId, isNull, reason: 'Clicking empty canvas must clear selection without proximity stealing');
    });

    testWidgets('Part Move and Rotate Command Discipline: moves ONLY on move, rotates in place ONLY on rotate', (tester) async {
      final vm = AssemblyStudioViewModel();
      vm.loadStandardLadderDemo();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 800,
              child: Assembly3DViewport(viewModel: vm),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final rung2 = vm.doc.parts.firstWhere((p) => p.id == 'rung_2');
      // Unbond rung2 so it acts as an independent entity for testing Move and Rotate tool discipline
      vm.breakAllBondsForPart('rung_2');
      final originalPos = CadPoint3D(rung2.position.x, rung2.position.y, rung2.position.z);
      final originalRot = CadPoint3D(rung2.rotationDeg.x, rung2.rotationDeg.y, rung2.rotationDeg.z);
      final rungPosOnScreen = const Offset(366.9, 287.5);

      // 1. In Select mode: Dragging the part should NEVER move or rotate it!
      vm.setToolMode(SketchUpToolMode.select);
      await tester.pumpAndSettle();

      final gesture1 = await tester.startGesture(rungPosOnScreen);
      await tester.pump(const Duration(milliseconds: 50));
      await gesture1.moveBy(const Offset(60, 40));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture1.up();
      await tester.pumpAndSettle();

      expect(rung2.position.x, originalPos.x, reason: 'Part must not move in select mode');
      expect(rung2.position.y, originalPos.y, reason: 'Part must not move in select mode');
      expect(rung2.position.z, originalPos.z, reason: 'Part must not move in select mode');
      expect(rung2.rotationDeg.z, originalRot.z, reason: 'Part must not rotate in select mode');

      // 2. In Move mode: Dragging the unbonded part should move its position
      vm.setToolMode(SketchUpToolMode.move);
      await tester.pumpAndSettle();

      final gesture2 = await tester.startGesture(rungPosOnScreen);
      await tester.pump(const Duration(milliseconds: 50));
      await gesture2.moveBy(const Offset(60, 40));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture2.up();
      await tester.pumpAndSettle();

      expect(rung2.position.x != originalPos.x || rung2.position.y != originalPos.y || rung2.position.z != originalPos.z,
          isTrue, reason: 'Part must move when move tool is active');

      // 3. In Rotate mode: Dragging the part should rotate in place (position remains unchanged!)
      final posBeforeRotate = CadPoint3D(rung2.position.x, rung2.position.y, rung2.position.z);

      vm.setToolMode(SketchUpToolMode.rotate);
      await tester.pumpAndSettle();

      // Drag at the exact new screen position of rung2 after move
      final rungNewScreenPos = rungPosOnScreen + const Offset(60, 40);
      final gesture3 = await tester.startGesture(rungNewScreenPos);
      await tester.pump(const Duration(milliseconds: 50));
      await gesture3.moveBy(const Offset(80, 0));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture3.up();
      await tester.pumpAndSettle();

      expect(
        rung2.rotationDeg.x != originalRot.x || rung2.rotationDeg.y != originalRot.y || rung2.rotationDeg.z != originalRot.z,
        isTrue,
        reason: 'Part must rotate when rotate tool is active',
      );
      expect(rung2.position.x, posBeforeRotate.x, reason: 'Position must not change during in-place rotation');
      expect(rung2.position.y, posBeforeRotate.y, reason: 'Position must not change during in-place rotation');
      expect(rung2.position.z, posBeforeRotate.z, reason: 'Position must not change during in-place rotation');
    });

    testWidgets('Welded Entity is NOT movable, draggable, or separable unless the bond/weld is broken', (tester) async {
      final vm = AssemblyStudioViewModel();
      vm.loadStandardLadderDemo();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 800,
              child: Assembly3DViewport(viewModel: vm),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final rung2 = vm.doc.parts.firstWhere((p) => p.id == 'rung_2');
      expect(vm.isPartBonded(rung2.id), isTrue, reason: 'Rung 2 has active welds');
      final initialPos = CadPoint3D(rung2.position.x, rung2.position.y, rung2.position.z);
      final initialRot = CadPoint3D(rung2.rotationDeg.x, rung2.rotationDeg.y, rung2.rotationDeg.z);
      final rungPosOnScreen = const Offset(366.9, 287.5);

      // 1. Move tool: dragging a welded part must NOT move it!
      vm.setToolMode(SketchUpToolMode.move);
      await tester.pumpAndSettle();

      final gestureMove = await tester.startGesture(rungPosOnScreen);
      await tester.pump(const Duration(milliseconds: 50));
      await gestureMove.moveBy(const Offset(80, 50));
      await tester.pump(const Duration(milliseconds: 50));
      await gestureMove.up();
      await tester.pumpAndSettle();

      expect(rung2.position.x, initialPos.x, reason: 'Welded part must NOT move when dragged');
      expect(rung2.position.y, initialPos.y, reason: 'Welded part must NOT move when dragged');
      expect(rung2.position.z, initialPos.z, reason: 'Welded part must NOT move when dragged');
      expect(vm.vcbLabel, contains('Welded Entity'));

      // 2. Rotate tool: dragging a welded part must NOT rotate it!
      vm.setToolMode(SketchUpToolMode.rotate);
      await tester.pumpAndSettle();

      final gestureRotate = await tester.startGesture(rungPosOnScreen);
      await tester.pump(const Duration(milliseconds: 50));
      await gestureRotate.moveBy(const Offset(80, 0));
      await tester.pump(const Duration(milliseconds: 50));
      await gestureRotate.up();
      await tester.pumpAndSettle();

      expect(rung2.rotationDeg.z, initialRot.z, reason: 'Welded part must NOT rotate when dragged');

      // 3. Break the weld: now the part becomes movable!
      vm.selectPart('rung_2');
      vm.separateSelectedPart();
      expect(vm.isPartBonded(rung2.id), isFalse, reason: 'Bonds broken via separateSelectedPart');

      vm.setToolMode(SketchUpToolMode.move);
      await tester.pumpAndSettle();

      final gestureFreeMove = await tester.startGesture(rungPosOnScreen);
      await tester.pump(const Duration(milliseconds: 50));
      await gestureFreeMove.moveBy(const Offset(80, 50));
      await tester.pump(const Duration(milliseconds: 50));
      await gestureFreeMove.up();
      await tester.pumpAndSettle();

      expect(rung2.position.x != initialPos.x || rung2.position.y != initialPos.y, isTrue,
          reason: 'Entity becomes movable once bond/weld is broken');
    });

    test('Phase 1: Measurements VCB & Linear Array Multiplier (*N)', () {
      final vm = AssemblyStudioViewModel();
      vm.loadStandardLadderDemo();
      final initialPartCount = vm.doc.parts.length;
      final initialWeldCount = vm.doc.welds.length;
      final rung = vm.doc.parts.firstWhere((p) => p.type == AssemblyPartType.rung);

      // Record a manual move delta of 250mm along Z
      vm.recordLastMove(
        partId: rung.id,
        delta: const CadPoint3D(0.0, 0.0, 250.0),
      );

      // User types *4 into the Measurements VCB to create 4 total instances (3 copies)
      final success = vm.submitVcbInput('*4');
      expect(success, isTrue);

      // 3 additional parts created
      expect(vm.doc.parts.length, initialPartCount + 3);
      // New parts are rungs positioned at rung.z + 250, + 500, + 750
      final lastCreated = vm.doc.parts.last;
      expect(lastCreated.position.z, rung.position.z + 750.0);
      // Welds were created for each copy connecting to parent rail
      expect(vm.doc.welds.length, greaterThan(initialWeldCount));
      // VCB state reflects the array creation
      expect(vm.vcbLabel, 'Array');
      expect(vm.vcbValue, contains('*4'));
    });

    test('Phase 1: Measurements VCB & Linear Array Divide (/N)', () {
      final vm = AssemblyStudioViewModel();
      vm.loadStandardLadderDemo();
      final initialPartCount = vm.doc.parts.length;
      final rung = vm.doc.parts.firstWhere((p) => p.type == AssemblyPartType.rung);

      final initialZ = rung.position.z;
      // User moved rung to the end of the span (+900mm along Z)
      rung.position = CadPoint3D(rung.position.x, rung.position.y, initialZ + 900.0);
      vm.recordLastMove(
        partId: rung.id,
        delta: const CadPoint3D(0.0, 0.0, 900.0),
      );

      // User types /3 to divide span into 3 segments (places 2 intermediate rungs at 300mm and 600mm)
      final success = vm.submitVcbInput('/3');
      expect(success, isTrue);

      expect(vm.doc.parts.length, initialPartCount + 2);
      final rungs = vm.doc.parts.where((p) => p.type == AssemblyPartType.rung).toList();
      final copy1 = rungs[rungs.length - 2];
      final copy2 = rungs[rungs.length - 1];
      expect(copy1.position.z, closeTo(initialZ + 300.0, 0.01));
      expect(copy2.position.z, closeTo(initialZ + 600.0, 0.01));
      expect(vm.vcbLabel, 'Divide');
      expect(vm.vcbValue, contains('/3'));
    });

    test('Phase 1: Explicit Distance and Angle in Measurements VCB', () {
      final vm = AssemblyStudioViewModel();
      vm.loadStandardLadderDemo();
      final rung = vm.doc.parts.firstWhere((p) => p.type == AssemblyPartType.rung);
      final initialX = rung.position.x;

      // Move rung slightly along X (e.g. 10mm drag)
      rung.position = CadPoint3D(initialX + 10.0, rung.position.y, rung.position.z);
      vm.recordLastMove(partId: rung.id, delta: const CadPoint3D(10.0, 0.0, 0.0));

      // User types exact distance '350' (or '350mm') into VCB
      final moveSuccess = vm.submitVcbInput('350mm');
      expect(moveSuccess, isTrue);
      // Rung position is updated to exactly initialX + 350
      expect(rung.position.x, closeTo(initialX + 350.0, 0.01));

      // Rotate part slightly and type exact angle '45'
      vm.recordLastRotate(partId: rung.id, deltaDeg: 12.0);
      final rotSuccess = vm.submitVcbInput('45°');
      expect(rotSuccess, isTrue);
      expect(rung.rotationDeg.z, closeTo(45.0, 0.01));
    });

    test('Phase 1: Ctrl+Move Instant Duplication (clonePartForMove)', () {
      final vm = AssemblyStudioViewModel();
      vm.loadStandardLadderDemo();
      final initialCount = vm.doc.parts.length;
      final rail = vm.doc.parts.firstWhere((p) => p.type == AssemblyPartType.straightRail);

      final clone = vm.clonePartForMove(rail);
      expect(vm.doc.parts.length, initialCount + 1);
      expect(clone.id != rail.id, isTrue);
      expect(clone.name, contains('Copy'));
      expect(clone.position.x, rail.position.x);
      expect(clone.position.y, rail.position.y);
      expect(clone.position.z, rail.position.z);
      expect(vm.doc.selectedPartId, clone.id);
      expect(vm.doc.selectedPartIds.contains(clone.id), isTrue);
    });

    test('Phase 1: Multi-Click Hierarchy (selectPartBodyOrGroup)', () {
      final vm = AssemblyStudioViewModel();
      vm.loadStandardLadderDemo();
      final rail = vm.doc.parts.firstWhere((p) => p.type == AssemblyPartType.straightRail);
      expect(rail.weldedToPartIds, isNotEmpty);

      // Triple-click on rail selects the whole physical body (rail + all welded rungs)
      vm.selectPartBodyOrGroup(rail.id);
      expect(vm.doc.selectedPartIds.contains(rail.id), isTrue);
      for (final weldedRungId in rail.weldedToPartIds) {
        expect(vm.doc.selectedPartIds.contains(weldedRungId), isTrue);
      }
    });

    testWidgets('Phase 1: Measurements VCB HUD in Viewport displays and processes typing', (tester) async {
      final vm = AssemblyStudioViewModel();
      vm.loadStandardLadderDemo();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Assembly3DViewport(viewModel: vm),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // VCB HUD is rendered on the bottom right
      expect(find.text('MEASUREMENTS'), findsOneWidget);

      final vcbTextField = find.byType(TextField).first;
      expect(vcbTextField, findsOneWidget);

      // Type an explicit dimension into VCB and submit
      await tester.enterText(vcbTextField, '*5');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // Submit via Enter is accepted by VCB handler
      expect(vm.vcbLabel, isNotNull);
    });

    // =========================================================================
    // PHASE 2: READY-MADE LADDER PARTS & SAFETY CAGE ACCESSORIES TESTS
    // =========================================================================
    test('Phase 2: Procedural 3D mesh generation for all new ladder accessories', () {
      final accessories = [
        AssemblyPart(
          id: 'test_walkthrough',
          name: 'Walk-Through Stile',
          type: AssemblyPartType.walkThroughStile,
          length: 1060.0,
          height: 100.0,
          flangeWidth: 30.0,
        ),
        AssemblyPart(
          id: 'test_boxtube',
          name: 'Box Tube Stile',
          type: AssemblyPartType.boxTubeStile,
          length: 2000.0,
          height: 60.0,
          flangeWidth: 40.0,
        ),
        AssemblyPart(
          id: 'test_diamond_rung',
          name: 'Diamond Grip-Strut',
          type: AssemblyPartType.diamondGripRung,
          length: 400.0,
          height: 40.0,
          flangeWidth: 20.0,
        ),
        AssemblyPart(
          id: 'test_step_tread',
          name: 'Wide Step Tread',
          type: AssemblyPartType.wideStepTread,
          length: 500.0,
          height: 80.0,
          flangeWidth: 25.0,
        ),
        AssemblyPart(
          id: 'test_bell_hoop',
          name: 'Bell Entry Hoop',
          type: AssemblyPartType.safetyCageBellHoop,
          length: 50.0,
          height: 700.0,
          flangeWidth: 700.0,
        ),
        AssemblyPart(
          id: 'test_standard_hoop',
          name: 'Standard Cage Hoop',
          type: AssemblyPartType.safetyCageHoop,
          length: 50.0,
          height: 700.0,
          flangeWidth: 700.0,
        ),
        AssemblyPart(
          id: 'test_strap',
          name: 'Vertical Cage Strap',
          type: AssemblyPartType.cageStrap,
          length: 2000.0,
          height: 30.0,
          flangeWidth: 30.0,
        ),
        AssemblyPart(
          id: 'test_standoff',
          name: 'Wall Standoff Bracket',
          type: AssemblyPartType.standoffBracket,
          length: 175.0,
          height: 80.0,
          flangeWidth: 50.0,
        ),
        AssemblyPart(
          id: 'test_foot_plate',
          name: 'Base Anchor Shoe Plate',
          type: AssemblyPartType.baseFootPlate,
          length: 120.0,
          height: 100.0,
          thickness: 6.0,
        ),
        AssemblyPart(
          id: 'test_splice',
          name: 'Stile Splice Fishplate',
          type: AssemblyPartType.splicePlate,
          length: 250.0,
          height: 80.0,
          thickness: 3.0,
        ),
        AssemblyPart(
          id: 'test_gate',
          name: 'OSHA Safety Swing Gate',
          type: AssemblyPartType.swingGate,
          length: 600.0,
          height: 420.0,
        ),
      ];

      for (final part in accessories) {
        final mesh = part.build3DMesh();
        expect(mesh.polygons.isNotEmpty, isTrue, reason: 'Polygons empty for ${part.type}');
        expect(mesh.boundWidth > 0, isTrue, reason: 'boundWidth invalid for ${part.type}');
        expect(mesh.boundLength > 0, isTrue, reason: 'boundLength invalid for ${part.type}');
        for (final poly in mesh.polygons) {
          expect(poly.vertices.length >= 3, isTrue, reason: 'Degenerate poly in ${part.type}');
          expect(poly.normal, isNotNull);
        }
      }
    });

    test('Phase 2: Safety Cage Assembly Generator builds hoops, straps, and welds', () {
      final vm = AssemblyStudioViewModel();
      vm.loadStandardLadderDemo();

      final initialPartCount = vm.doc.parts.length;
      final initialWeldCount = vm.doc.welds.length;

      // Generate cage
      vm.generateSafetyCageAssembly(
        startHeight: 400.0,
        totalHeight: 1000.0,
        hoopDiameter: 700.0,
        strapCount: 5,
        hoopSpacing: 300.0,
      );

      expect(vm.doc.parts.length, greaterThan(initialPartCount));
      expect(vm.doc.welds.length, greaterThan(initialWeldCount));

      // Check bell entry hoop and standard hoops exist
      final bellHoops = vm.doc.parts.where((p) => p.type == AssemblyPartType.safetyCageBellHoop).toList();
      final standardHoops = vm.doc.parts.where((p) => p.type == AssemblyPartType.safetyCageHoop).toList();
      final straps = vm.doc.parts.where((p) => p.type == AssemblyPartType.cageStrap).toList();

      expect(bellHoops.length, 1);
      expect(standardHoops.length, greaterThanOrEqualTo(1));
      expect(straps.length, 5);

      // Verify virtual grouping
      expect(bellHoops.first.groupName, contains('Safety Cage Assembly'));
      expect(straps.first.groupId, equals(bellHoops.first.groupId));

      // Verify persistent weld joints are connected
      final cageWelds = vm.doc.welds.where((w) => w.jointDescription.contains('Hoop') || w.jointDescription.contains('Strap')).toList();
      expect(cageWelds.isNotEmpty, isTrue);
    });

    test('Phase 2: Walk-Through Parapet Stiles Generator adds flared extensions with splice welds', () {
      final vm = AssemblyStudioViewModel();
      vm.loadStandardLadderDemo();

      final initialPartCount = vm.doc.parts.length;
      vm.addWalkThroughParapetStiles(extensionHeight: 1060.0);

      final walkThroughs = vm.doc.parts.where((p) => p.type == AssemblyPartType.walkThroughStile).toList();
      expect(walkThroughs.length, 2);
      expect(vm.doc.parts.length, initialPartCount + 2);

      // Verify splice welds
      final spliceWelds = vm.doc.welds.where((w) => w.jointDescription.contains('Splice')).toList();
      expect(spliceWelds.length, 2);
    });

    test('Phase 2: Wall Standoff Brackets Generator adds brackets along ladder rails', () {
      final vm = AssemblyStudioViewModel();
      vm.loadStandardLadderDemo();

      final initialPartCount = vm.doc.parts.length;
      vm.addWallStandoffBrackets(standoffDepth: 175.0, spacing: 500.0);

      final standoffs = vm.doc.parts.where((p) => p.type == AssemblyPartType.standoffBracket).toList();
      expect(standoffs.length, greaterThanOrEqualTo(2));
      expect(vm.doc.parts.length, greaterThan(initialPartCount));

      // Verify bracket welds
      final bracketWelds = vm.doc.welds.where((w) => w.jointDescription.contains('Bracket Mounting')).toList();
      expect(bracketWelds.length, equals(standoffs.length));
    });

    test('Phase 2: Base Foot Plates & Safety Swing Gate Generators', () {
      final vm = AssemblyStudioViewModel();
      vm.loadStandardLadderDemo();

      // Base shoes
      vm.addBaseFootPlates();
      final footPlates = vm.doc.parts.where((p) => p.type == AssemblyPartType.baseFootPlate).toList();
      expect(footPlates.length, 2);

      // Swing gate
      vm.addSafetySwingGate();
      final gates = vm.doc.parts.where((p) => p.type == AssemblyPartType.swingGate).toList();
      expect(gates.length, 1);
      expect(gates.first.jointType, equals(AssemblyJointType.hinged));
    });

    test('Phase 2: Place pending part supports all Phase 2 accessory types', () {
      final vm = AssemblyStudioViewModel();
      for (final type in [
        AssemblyPartType.walkThroughStile,
        AssemblyPartType.boxTubeStile,
        AssemblyPartType.diamondGripRung,
        AssemblyPartType.wideStepTread,
        AssemblyPartType.safetyCageHoop,
        AssemblyPartType.safetyCageBellHoop,
        AssemblyPartType.cageStrap,
        AssemblyPartType.standoffBracket,
        AssemblyPartType.baseFootPlate,
        AssemblyPartType.splicePlate,
        AssemblyPartType.swingGate,
      ]) {
        vm.setPendingPlacement(PendingPartPlacement(
          type: type,
          name: 'Test ${type.name}',
          length: 500.0,
          height: 100.0,
        ));
        final placed = vm.placePendingPartAt(const CadPoint3D(100.0, 200.0, 50.0));
        expect(placed, isNotNull);
        expect(placed!.type, equals(type));
        expect(placed.position.x, 100.0);
      }
    });

    test('Phase 3: Component Instancing & Parametric Synchronization', () {
      final vm = AssemblyStudioViewModel();
      vm.loadStandardLadderDemo();

      final firstRung = vm.doc.parts.firstWhere((p) => p.type == AssemblyPartType.rung);
      expect(firstRung.isComponentInstance, isFalse);

      // Clone for move (Ctrl+Move) links template and clone as component instances
      final clonedRung = vm.clonePartForMove(firstRung);
      expect(firstRung.isComponentInstance, isTrue);
      expect(clonedRung.isComponentInstance, isTrue);
      expect(firstRung.componentDefinitionId, equals(clonedRung.componentDefinitionId));
      expect(vm.getComponentInstanceCount(firstRung.componentDefinitionId), 2);

      // Update dimension on first rung -> automatically syncs to cloned rung!
      vm.selectPart(firstRung.id);
      vm.updateSelectedLength(720.0);
      expect(firstRung.length, 720.0);
      expect(clonedRung.length, 720.0);

      // Add sketch hole on first rung -> automatically syncs to cloned rung!
      vm.addSketchFeature(featureType: 'circle_hole', localCenter: const CadPoint2D(100.0, 10.0), widthMm: 8.0, heightMm: 8.0);
      expect(firstRung.sketches.any((s) => s.featureType == 'circle_hole'), isTrue);
      expect(clonedRung.sketches.any((s) => s.featureType == 'circle_hole'), isTrue);

      // Make Unique detaches cloned rung
      vm.makePartUnique(clonedRung.id);
      expect(clonedRung.isComponentInstance, isFalse);
      expect(clonedRung.componentDefinitionId, isNull);

      // Subsequent edits to first rung no longer affect detached unique rung
      vm.updateSelectedLength(850.0);
      expect(firstRung.length, 850.0);
      expect(clonedRung.length, 720.0); // Preserved previous length!
    });

    test('Phase 3: Linear Array propagates Component Definition across all copies', () {
      final vm = AssemblyStudioViewModel();
      vm.doc.parts.clear();
      vm.doc.welds.clear();

      final template = AssemblyPart(
        id: 'test_rung',
        name: 'Array Template Rung',
        type: AssemblyPartType.diamondGripRung,
        length: 450.0,
        height: 30.0,
        thickness: 2.0,
      );
      vm.doc.parts.add(template);

      vm.recordLastMove(
        partId: template.id,
        delta: const CadPoint3D(0.0, 0.0, 300.0),
      );
      vm.createLinearArray(4); // 4 total copies

      final rungs = vm.doc.parts.where((p) => p.type == AssemblyPartType.diamondGripRung).toList();
      expect(rungs.length, 4);
      final sharedDefId = template.componentDefinitionId;
      expect(sharedDefId, isNotNull);
      for (final r in rungs) {
        expect(r.componentDefinitionId, equals(sharedDefId));
      }

      // Modifying one rungs thickness syncs across all 4 linked copies
      vm.selectPart(template.id);
      vm.updateSelectedThickness(3.5);
      for (final r in rungs) {
        expect(r.thickness, 3.5);
      }
    });

    test('Phase 3: Rotational Copy & Radial Multiplier (*N and /N)', () {
      final vm = AssemblyStudioViewModel();
      vm.doc.parts.clear();
      vm.doc.welds.clear();

      final spoke = AssemblyPart(
        id: 'spoke_1',
        name: 'Wheel Spoke',
        type: AssemblyPartType.bar,
        length: 300.0,
        height: 20.0,
        position: const CadPoint3D(0.0, 0.0, 0.0),
      );
      vm.doc.parts.add(spoke);

      // 1. Single Rotational Copy
      final rotatedCopy = vm.rotateAndCopyPart(spoke.id, 45.0);
      expect(rotatedCopy, isNotNull);
      expect(rotatedCopy.rotationDeg.z, 45.0);
      expect(rotatedCopy.componentDefinitionId, equals(spoke.componentDefinitionId));
      expect(vm.lastRotateDeltaDeg, 45.0);

      // 2. Radial Multiplier via VCB (*6)
      final handled = vm.submitVcbInput('*6');
      expect(handled, isTrue);
      final radialCopies = vm.doc.parts.where((p) => p.type == AssemblyPartType.bar).toList();
      expect(radialCopies.length, greaterThanOrEqualTo(6));

      // 3. Radial Divide via VCB (/3)
      final spoke2 = vm.doc.parts.first;
      vm.recordLastRotate(partId: spoke2.id, deltaDeg: 90.0);
      vm.submitVcbInput('/3');
      expect(vm.vcbLabel, equals('Radial Array'));
    });

    test('SketchUp 3-Click Rotate: Off-Center Pivot, Axis Locking, and Radial Array (*N / /N)', () {
      final vm = AssemblyStudioViewModel();
      vm.doc.parts.clear();
      vm.doc.welds.clear();

      final part = AssemblyPart(
        id: 'r_part_1',
        name: 'Rotated Bracket',
        type: AssemblyPartType.bar,
        length: 100.0,
        height: 50.0,
        position: const CadPoint3D(200.0, 0.0, 0.0),
      );
      vm.doc.parts.add(part);

      // 1. Arrow key axis locking
      vm.toggleLockedAxis(GizmoAxis.x);
      expect(vm.lockedAxis, equals(GizmoAxis.x));
      vm.toggleLockedAxis(GizmoAxis.y);
      expect(vm.lockedAxis, equals(GizmoAxis.y));
      vm.toggleLockedAxis(GizmoAxis.z);
      expect(vm.lockedAxis, equals(GizmoAxis.z));

      // 2. Off-Center Pivot Rotation record
      const customPivot = CadPoint3D(100.0, 0.0, 0.0);
      vm.recordLastRotate(
        partId: part.id,
        deltaDeg: 45.0,
        centerPoint: customPivot,
        axis: GizmoAxis.z,
      );
      expect(vm.lastRotateCenterPoint, equals(customPivot));
      expect(vm.lastRotateAxis, equals(GizmoAxis.z));

      // 3. Radial array via VCB *4 around custom pivot
      final handledMultiply = vm.submitVcbInput('*4');
      expect(handledMultiply, isTrue);
      final brackets = vm.doc.parts.where((p) => p.name.startsWith('Rotated Bracket')).toList();
      expect(brackets.length, equals(4));

      // Verify that all copies orbit around the custom pivot (distance from pivot is ~100mm)
      for (final b in brackets) {
        final dist = (b.position.x - customPivot.x) * (b.position.x - customPivot.x) +
            (b.position.y - customPivot.y) * (b.position.y - customPivot.y);
        expect(dist, closeTo(10000.0, 1.0));
      }

      // 4. Radial divide via VCB /2 around custom pivot
      vm.doc.parts.clear();
      vm.doc.parts.add(part);
      vm.recordLastRotate(
        partId: part.id,
        deltaDeg: 90.0,
        centerPoint: customPivot,
        axis: GizmoAxis.z,
      );
      final handledDivide = vm.submitVcbInput('/2');
      expect(handledDivide, isTrue);
      final dividedBrackets = vm.doc.parts.where((p) => p.name.startsWith('Rotated Bracket')).toList();
      expect(dividedBrackets.length, equals(2)); // Original + 1 interior segment at 45°
    });

    test('Phase 3: Auto-Span Face-to-Face Bridging Tool connects stiles with dual welds', () {
      final vm = AssemblyStudioViewModel();
      vm.doc.parts.clear();
      vm.doc.welds.clear();

      // Spawn two stiles separated along Y by 450mm
      final stileLeft = AssemblyPart(
        id: 'stile_left',
        name: 'Left Stile',
        type: AssemblyPartType.boxTubeStile,
        length: 2000.0,
        height: 60.0,
        position: const CadPoint3D(0.0, 0.0, 0.0),
      );
      final stileRight = AssemblyPart(
        id: 'stile_right',
        name: 'Right Stile',
        type: AssemblyPartType.boxTubeStile,
        length: 2000.0,
        height: 60.0,
        position: const CadPoint3D(0.0, 450.0, 0.0),
      );
      vm.doc.parts.addAll([stileLeft, stileRight]);

      // Set bridge mode and click first stile
      vm.setToolMode(SketchUpToolMode.bridge);
      expect(vm.activeToolMode, equals(SketchUpToolMode.bridge));

      vm.startBridge(stileLeft.id);
      expect(vm.bridgeSourcePartId, equals(stileLeft.id));

      // Click second stile -> auto spans bridge rung & creates dual welds!
      final bridgedRung = vm.bridgeParts(
        stileLeft.id,
        stileRight.id,
        distanceX: 500.0,
        rungType: AssemblyPartType.diamondGripRung,
      );
      expect(bridgedRung, isNotNull);
      expect(bridgedRung!.length, 450.0); // Exact span distance!
      expect(bridgedRung.position.x, 500.0);
      expect(bridgedRung.type, equals(AssemblyPartType.diamondGripRung));

      // Dual fillet welds verified
      expect(vm.doc.welds.length, 2);
      expect(vm.doc.welds.any((w) => w.partAId == stileLeft.id && w.partBId == bridgedRung.id), isTrue);
      expect(vm.doc.welds.any((w) => w.partAId == stileRight.id && w.partBId == bridgedRung.id), isTrue);
      expect(stileLeft.weldedToPartIds.contains(bridgedRung.id), isTrue);
      expect(stileRight.weldedToPartIds.contains(bridgedRung.id), isTrue);
      expect(bridgedRung.weldedToPartIds.contains(stileLeft.id), isTrue);
      expect(bridgedRung.weldedToPartIds.contains(stileRight.id), isTrue);

      // Slots punched on both box tube stiles
      expect(stileLeft.sketches.any((s) => s.isRungSlotEntity), isTrue);
      expect(stileRight.sketches.any((s) => s.isRungSlotEntity), isTrue);
    });

    testWidgets('Phase 3: Inspector Panel displays Component Instance Banner and Make Unique action', (tester) async {
      final vm = AssemblyStudioViewModel();
      vm.loadStandardLadderDemo();

      // Make a component
      final part = vm.doc.parts.first;
      vm.makePartComponent(part.id);
      vm.selectPart(part.id);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AssemblyInspectorPanel(viewModel: vm),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Component Header Badge and Banner
      expect(find.textContaining('COMPONENT'), findsWidgets);
      expect(find.text('Make Unique'), findsOneWidget);

      // Tap Make Unique
      await tester.tap(find.text('Make Unique'));
      await tester.pumpAndSettle();

      expect(part.isComponentInstance, isFalse);
      expect(find.text('Make Component'), findsOneWidget);
    });

    test('Phase 4: Push/Pull Void Hole Punching cuts CNC shapes and generates 3D bore walls', () {
      final vm = AssemblyStudioViewModel();
      vm.loadStandardLadderDemo();

      final rail = vm.doc.parts.firstWhere((p) => p.type == AssemblyPartType.straightRail);

      // Punch void circular hole on web
      vm.punchVoidHole(
        partId: rail.id,
        targetFace: 'web',
        localCenter: const CadPoint2D(200.0, 40.0),
        shape: 'circle_hole',
        widthMm: 16.0,
      );

      // Punch void obround slot on web
      vm.punchVoidHole(
        partId: rail.id,
        targetFace: 'web',
        localCenter: const CadPoint2D(500.0, 40.0),
        shape: 'obround_slot',
        widthMm: 50.0,
        heightMm: 20.0,
      );

      // Punch rectangular cutout on top flange
      vm.punchVoidHole(
        partId: rail.id,
        targetFace: 'flange_top',
        localCenter: const CadPoint2D(350.0, 10.0),
        shape: 'rect_cut',
        widthMm: 30.0,
        heightMm: 15.0,
      );

      // Verify sketch features created
      expect(rail.sketches.any((s) => s.featureType == 'circle_hole' && s.widthMm == 16.0), isTrue);
      expect(rail.sketches.any((s) => s.featureType == 'obround_slot' && s.widthMm == 50.0), isTrue);
      expect(rail.sketches.any((s) => s.targetFace == 'flange_top'), isTrue);

      // Build 3D mesh and verify hole boundary loops
      final mesh = rail.build3DMesh();
      final webPoly = mesh.polygons.firstWhere((p) => p.faceId == '${rail.id}_web');
      expect(webPoly.holes.isNotEmpty, isTrue);

      final topFlangePoly = mesh.polygons.firstWhere((p) => p.faceId == '${rail.id}_flange_top');
      expect(topFlangePoly.holes.isNotEmpty, isTrue);

      // Verify extruded 3D bore wall polygons in thicknessPolygons
      expect(mesh.thicknessPolygons.any((p) => p.faceId.startsWith('${rail.id}_bore_')), isTrue);
    });

    test('Phase 4: Realistic 3D Fillet Weld Bead Mesh Generation with Scalloped Ripples', () {
      final vm = AssemblyStudioViewModel();
      vm.loadStandardLadderDemo();

      expect(vm.doc.welds.isNotEmpty, isTrue);
      final firstWeld = vm.doc.welds.first;

      // Verify weld mesh generation produces scalloped 3D polygons
      final mesh = vm.assemblyMesh;
      final weldPolys = mesh.polygons.where((p) => p.faceId == 'weld_${firstWeld.id}').toList();

      // Realistic 3D fillet weld bead has multiple ripple scallops + 2 end caps
      expect(weldPolys.length, greaterThanOrEqualTo(6));

      for (final poly in weldPolys) {
        expect(poly.vertices.length, greaterThanOrEqualTo(3));
        expect(poly.normal, isNotNull);
      }

      // Check authentic metallic weld bead color (dark gunmetal finish, zero blue tint, no yellow boxes, SS5)
      expect(weldPolys.first.color, equals(const Color(0xFF3F3F46)));

      // When translucent overlay is toggled off, reverts to solid dark tempered steel
      vm.toggleWeldOverlay();
      final solidMesh = vm.assemblyMesh;
      final solidWeldPolys = solidMesh.polygons.where((p) => p.faceId == 'weld_${firstWeld.id}').toList();
      expect(solidWeldPolys.first.color, equals(const Color(0xFF27272A)));
      vm.toggleWeldOverlay(); // Re-enable overlay

      // Select the weld bead directly -> changes to glowing electric cyan
      vm.selectWeld(firstWeld.id);
      final selectedMesh = vm.assemblyMesh;
      final selectedWeldPolys = selectedMesh.polygons.where((p) => p.faceId == 'weld_${firstWeld.id}').toList();
      expect(selectedWeldPolys.first.color, equals(const Color(0xFF00E5FF)));

      // Update weld size and seam length
      vm.updateSelectedWeldSize(8.0);
      vm.updateSelectedWeldLength(55.0);

      final updatedWeld = vm.selectedWeld!;
      expect(updatedWeld.weldSizeMm, 8.0);
      expect(updatedWeld.weldLengthMm, 55.0);
      expect(updatedWeld.throatMm, closeTo(0.7071 * 8.0, 0.01));
      expect(updatedWeld.weldSymbol, contains('8mm Fillet'));
    });

    test('Phase 4: Live OSHA 1910 & EN ISO 14122-4 Compliance Verification Engine & Auto-Fix', () {
      final vm = AssemblyStudioViewModel();
      vm.loadStandardLadderDemo();

      // Evaluate compliance on standard ladder
      final report = vm.evaluateLadderCompliance();
      expect(report.items.length, 5);
      expect(report.items.any((i) => i.id == 'rung_pitch'), isTrue);
      expect(report.items.any((i) => i.id == 'clear_width'), isTrue);
      expect(report.items.any((i) => i.id == 'wall_clearance'), isTrue);
      expect(report.items.any((i) => i.id == 'cage_height'), isTrue);
      expect(report.items.any((i) => i.id == 'parapet_extension'), isTrue);

      // Verify 1-Click Auto-Fix for Rung Pitch
      vm.autoFixRungSpacing(targetPitch: 280.0);
      final rungs = vm.doc.parts.where((p) => p.type == AssemblyPartType.rung).toList();
      final bool isAlongX = (rungs.map((r) => r.position.x).reduce(math.max) - rungs.map((r) => r.position.x).reduce(math.min)) > 50.0;
      if (isAlongX) {
        rungs.sort((a, b) => a.position.x.compareTo(b.position.x));
        for (int i = 0; i < rungs.length - 1; i++) {
          final pitch = rungs[i + 1].position.x - rungs[i].position.x;
          expect(pitch, closeTo(280.0, 0.01));
        }
      } else {
        rungs.sort((a, b) => a.position.z.compareTo(b.position.z));
        for (int i = 0; i < rungs.length - 1; i++) {
          final pitch = rungs[i + 1].position.z - rungs[i].position.z;
          expect(pitch, closeTo(280.0, 0.01));
        }
      }

      // Verify 1-Click Auto-Fix for Clear Width
      vm.autoFixClearWidth(targetWidth: 450.0);
      for (final r in rungs) {
        expect(r.length, 450.0);
      }
      final rightRail = vm.doc.parts.firstWhere((p) => p.id == 'rail_right');
      expect(rightRail.position.y, 450.0);

      // Verify 1-Click Auto-Fix for Wall Clearance
      vm.autoFixWallClearance(targetClearance: 200.0);
      final bracket = vm.doc.parts.firstWhere((p) => p.type == AssemblyPartType.standoffBracket);
      expect(bracket.length, 200.0);

      // Verify 1-Click Auto-Fix for Safety Cage Start Height
      vm.autoFixCageHeight(targetHeight: 2200.0);
      final hoops = vm.doc.parts.where((p) => p.type == AssemblyPartType.safetyCageHoop || p.type == AssemblyPartType.safetyCageBellHoop).toList();
      final entryHeight = hoops.map((h) => math.max(h.position.x, h.position.z)).reduce(math.min);
      expect(entryHeight, closeTo(2200.0, 1.0));

      // Verify 1-Click Auto-Fix for Walk-Through Parapet Extension
      vm.autoFixParapetExtension(targetExtension: 1100.0);
      final parapet = vm.doc.parts.firstWhere((p) => p.type == AssemblyPartType.walkThroughStile);
      expect(math.max(parapet.height, parapet.length), greaterThanOrEqualTo(1100.0));

      // Auto-Fix All brings the full ladder to 100% compliant PASS status!
      vm.autoFixAllComplianceIssues();
      final fullyCompliantReport = vm.evaluateLadderCompliance();
      expect(fullyCompliantReport.isCompliant, isTrue);
      expect(fullyCompliantReport.overallStatus, equals(ComplianceStatus.pass));
      expect(fullyCompliantReport.badgeLabel, contains('PASS'));
    });

    test('Phase 4: Bill of Materials (BOM) & Fabrication Cut List Generator', () {
      final vm = AssemblyStudioViewModel();
      vm.loadStandardLadderDemo();

      // Add accessories to enrich BOM
      vm.addWallStandoffBrackets();
      vm.addWalkThroughParapetStiles();

      final bom = vm.generateBillOfMaterials(materialGrade: 'Stainless Steel 304');
      expect(bom.items.isNotEmpty, isTrue);
      expect(bom.totalPartCount, equals(vm.doc.parts.length));
      expect(bom.totalWeightKg, greaterThan(0.0));
      expect(bom.totalWeldCount, equals(vm.doc.welds.length));
      expect(bom.totalWeldLengthMm, greaterThan(0.0));

      // Check CSV Export
      final csv = bom.toCsv();
      expect(csv, contains('Item,Part Mark,Description,Profile,Qty,Length (mm)'));
      expect(csv, contains('SR-01'));
      expect(csv, contains('CR-02'));
      expect(csv, contains('SUMMARY'));
      expect(csv, contains('Total Parts,${bom.totalPartCount}'));

      // Check Markdown Export
      final markdown = bom.toMarkdown();
      expect(markdown, contains('# Bill of Materials (BOM) & Fabrication Cut List'));
      expect(markdown, contains('| Item | Mark | Description | Profile | Qty | Cut Length | Unit Wt | Total Wt | Holes | Material |'));
      expect(markdown, contains('### Fabrication Weld Summary'));
      expect(markdown, contains('${bom.totalWeldCount} joints'));
    });

    testWidgets('Phase 4: Viewport & Inspector render Compliance Badge, BOM pill, and Weld Status bar', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final vm = AssemblyStudioViewModel();
      vm.loadStandardLadderDemo();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Assembly3DViewport(viewModel: vm),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Compliance HUD badge is displayed in viewport
      expect(find.textContaining('OSHA / ISO'), findsOneWidget);
      // Verify Cut List / BOM pill button is displayed in viewport
      expect(find.text('Cut List / BOM'), findsOneWidget);

      // Select a weld bead -> verify Selected Weld Status Bar appears at bottom
      final weld = vm.doc.welds.first;
      vm.selectWeld(weld.id);
      await tester.pumpAndSettle();

      expect(find.textContaining('Fillet'), findsAtLeastNWidgets(1));
      expect(find.text('Break Bond'), findsOneWidget);

      // Now pump Inspector Panel in empty state (no part selected)
      vm.selectPart(null);
      vm.selectWeld(null);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AssemblyInspectorPanel(viewModel: vm),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Compliance Card and BOM Card appear in Inspector Panel
      expect(find.text('SAFETY COMPLIANCE'), findsOneWidget);
      expect(find.text('BILL OF MATERIALS'), findsOneWidget);
    });

    testWidgets('Light / Dark Studio Background: Toggles background mode via VM and renders theme button', (tester) async {
      final vm = AssemblyStudioViewModel();
      expect(vm.isLightBackground, isTrue);

      // Toggle to Dark Studio Canvas
      vm.toggleBackgroundMode();
      expect(vm.isLightBackground, isFalse);

      // Toggle back to Light Studio Canvas
      vm.toggleBackgroundMode();
      expect(vm.isLightBackground, isTrue);

      // Explicit setter
      vm.setLightBackground(false);
      expect(vm.isLightBackground, isFalse);
      vm.setLightBackground(true);
      expect(vm.isLightBackground, isTrue);

      // Pump viewport with light background mode active
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Assembly3DViewport(viewModel: vm),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify movement toolbar is present and sun/moon toggle button works
      expect(find.byTooltip('Switch to Dark Studio Canvas (Alt+T)'), findsWidgets);

      // Tap the toolbar theme toggle button
      final toggleButton = find.byTooltip('Switch to Dark Studio Canvas (Alt+T)').first;
      await tester.tap(toggleButton);
      await tester.pumpAndSettle();

      // VM should now be dark mode
      expect(vm.isLightBackground, isFalse);
      expect(find.byTooltip('Switch to Light Studio Canvas (Alt+T)'), findsWidgets);
    });

    testWidgets('Whole App Light / Dark Theme: Dynamically switches all panels, menus, and interface widgets', (tester) async {
      final vm = AssemblyStudioViewModel();
      expect(vm.isLightMode, isTrue);

      await tester.pumpWidget(
        MaterialApp(
          home: AssemblyStudioScreen(viewModel: vm),
        ),
      );
      await tester.pumpAndSettle();

      // Initially Light Mode
      expect(find.text('SCENE OUTLINER'), findsOneWidget);
      expect(find.text('PROPERTY GRID'), findsOneWidget);
      expect(find.textContaining('Theme: LIGHT'), findsOneWidget);

      // Toggle Theme via ViewModel
      vm.toggleTheme();
      await tester.pumpAndSettle();

      expect(vm.isLightMode, isFalse);
      expect(find.textContaining('Theme: DARK'), findsOneWidget);

      // Verify Theme toggle button in top menu bar works
      final menuToggle = find.byTooltip('Switch to Light Studio Canvas (Alt+T)');
      expect(menuToggle, findsWidgets);
      await tester.tap(menuToggle.first);
      await tester.pumpAndSettle();

      expect(vm.isLightMode, isTrue);
      expect(find.textContaining('Theme: LIGHT'), findsOneWidget);
    });

    testWidgets('Precision 3D Hit-Testing: Direct click selects exact frontmost entity without proximity stealing', (tester) async {
      final vm = AssemblyStudioViewModel();
      await tester.pumpWidget(
        MaterialApp(
          home: AssemblyStudioScreen(viewModel: vm),
        ),
      );
      await tester.pumpAndSettle();

      // Enter direct sketch mode to verify SingleChildScrollView doesn't throw unbounded RenderFlex
      final rail = vm.doc.parts.first;
      vm.focusPartAndEnterSketch(rail.id);
      await tester.pumpAndSettle();

      expect(vm.isSketchMode, isTrue);
      expect(find.textContaining('Direct Sketch:'), findsOneWidget);
      expect(find.text('3D Movement Locked'), findsOneWidget);

      // Verify no assertion errors were thrown during performLayout
      expect(tester.takeException(), isNull);

      // Exit sketch mode
      vm.finishSketch();
      await tester.pumpAndSettle();
      expect(vm.isSketchMode, isFalse);
    });

    test('PerspectiveCamera screenPointToRay and worldToScreen check', () {
      final cam = PerspectiveCamera(position: vm_math.Vector3(0, 0, 100), target: vm_math.Vector3(0, 0, 0));
      final ray = cam.screenPointToRay(const Offset(400, 300), const Size(800, 600));
      expect(ray, isNotNull);
      final dirNorm = ray.direction.normalized();
      expect(dirNorm.z, closeTo(-1.0, 1e-3));

      final cameraNode = Node(name: 'CameraNode');
      final cameraComp = CameraComponent(
        projection: PerspectiveProjection(fovRadiansY: 45.0 * vm_math.degrees2Radians, near: 1.0, far: 10000.0),
      );
      cameraNode.addComponent(cameraComp);
      cameraNode.lookAtFrom(vm_math.Vector3(0, 0, 100), vm_math.Vector3(0, 0, 0));
      final nodeCam = cameraComp.toCamera();
      final ray2 = nodeCam.screenPointToRay(const Offset(400, 300), const Size(800, 600));
      expect(ray2, isNotNull);
      final dirNorm2 = ray2.direction.normalized();
      expect(dirNorm2.z, closeTo(-1.0, 1e-3));

      final screenPt = nodeCam.worldToScreen(vm_math.Vector3(0, 0, 0), const Size(800, 600));
      expect(screenPt, isNotNull);
      expect(screenPt!.dx, closeTo(400.0, 1.0));
      expect(screenPt.dy, closeTo(300.0, 1.0));

      final behindPt = nodeCam.worldToScreen(vm_math.Vector3(0, 0, 200), const Size(800, 600));
      expect(behindPt, isNull);
    });

    test('AssemblyRaycaster: Ray hits frontmost polygon, detects holes, and handles empty space correctly', () {
      // Create a test mesh with 2 overlapping horizontal plates (front at z=20, back at z=0)
      // Front plate has a central hole of 20x20
      final frontPlate = CadFoldedPolygon3D(
        faceId: 'front_plate',
        normal: const CadPoint3D(0, 0, 1),
        vertices: const [
          CadPoint3D(-50, -50, 20),
          CadPoint3D(50, -50, 20),
          CadPoint3D(50, 50, 20),
          CadPoint3D(-50, 50, 20),
        ],
        holes: const [
          [
            CadPoint3D(-10, -10, 20),
            CadPoint3D(10, -10, 20),
            CadPoint3D(10, 10, 20),
            CadPoint3D(-10, 10, 20),
          ],
        ],
      );

      final backPlate = CadFoldedPolygon3D(
        faceId: 'back_plate',
        normal: const CadPoint3D(0, 0, 1),
        vertices: const [
          CadPoint3D(-50, -50, 0),
          CadPoint3D(50, -50, 0),
          CadPoint3D(50, 50, 0),
          CadPoint3D(-50, 50, 0),
        ],
      );

      final mesh = FoldedMeshResult(
        polygons: [frontPlate, backPlate],
        filletPolygons: const [],
        thicknessPolygons: const [],
        center: const CadPoint3D(0, 0, 10),
        boundWidth: 100,
        boundLength: 100,
        boundHeight: 20,
      );

      // 1. Ray aimed at solid area of front plate (at x=25, y=25):
      final hit1 = AssemblyRaycaster.raycast(
        rayOrigin: vm_math.Vector3(25, 25, 100),
        rayDirection: vm_math.Vector3(0, 0, -1),
        mesh: mesh,
      );
      expect(hit1, isNotNull);
      expect(hit1!.polygon.faceId, equals('front_plate'));
      expect(hit1.distance, closeTo(80.0, 1e-3));
      expect(hit1.isFrontFacing, isTrue);

      // 2. Ray aimed through hole in front plate (at x=0, y=0):
      // Passes through front plate hole, should hit back plate!
      final hitHole = AssemblyRaycaster.raycast(
        rayOrigin: vm_math.Vector3(0, 0, 100),
        rayDirection: vm_math.Vector3(0, 0, -1),
        mesh: mesh,
      );
      expect(hitHole, isNotNull);
      expect(hitHole!.polygon.faceId, equals('back_plate'));
      expect(hitHole.distance, closeTo(100.0, 1e-3));

      // 3. Ray aimed into empty space (at x=200, y=200):
      final hitEmpty = AssemblyRaycaster.raycast(
        rayOrigin: vm_math.Vector3(200, 200, 100),
        rayDirection: vm_math.Vector3(0, 0, -1),
        mesh: mesh,
      );
      expect(hitEmpty, isNull);
    });

    test('Weld Seam Placement & Orientation (AWS D1.1 / ISO 2553 & SS3, SS4, SS5)', () {
      final vm = AssemblyStudioViewModel();
      vm.loadStandardLadderDemo();

      // Verify left rail welds
      final leftWelds = vm.doc.welds.where((w) => w.partAId == 'rail_left').toList();
      expect(leftWelds.length, 4);

      for (final weld in leftWelds) {
        // Seam axis must be along X axis (transverse width of the rung)
        expect(weld.weldAxis.x, equals(1.0));
        expect(weld.weldAxis.y, equals(0.0));
        expect(weld.weldAxis.z, equals(0.0));

        // Primary root point must sit at contact seam on rail web (Y = 0) at top of rung (Z = 60)
        expect(weld.weldPoint.y, equals(0.0));
        expect(weld.weldPoint.z, equals(60.0)); // Top seam

        // Both sides fillet must be true per SS4
        expect(weld.bothSides, isTrue);
        expect(weld.secondWeldPoint, isNotNull);
        expect(weld.secondWeldPoint!.y, equals(0.0));
        expect(weld.secondWeldPoint!.z, equals(40.0)); // Bottom seam

        // Leg 1 must point along rail web (Z), Leg 2 inward along rung surface (Y)
        expect(weld.legDir1!.z, equals(1.0));
        expect(weld.legDir2!.y, equals(1.0));

        // Opposing Leg 1 points down (-Z), Leg 2 inward (Y)
        expect(weld.secondLegDir1!.z, equals(-1.0));
        expect(weld.secondLegDir2!.y, equals(1.0));

        // Theoretical throat formula t = 0.707 * a per SS5
        expect(weld.throatMm, closeTo(0.7071 * weld.weldSizeMm, 0.01));
        expect(weld.weldSymbol, equals('△△ 6mm Fillet (Both Sides)'));
      }

      // Verify 3D mesh geometry:
      final mesh = vm.assemblyMesh;
      final weldPolygons = mesh.polygons.where((p) => p.faceId.startsWith('weld_')).toList();
      expect(weldPolygons.isNotEmpty, isTrue);

      for (final poly in weldPolygons) {
        // Must be valid triangles or planar quadrilaterals (NO 5-vertex non-planar hourglass polygons)
        expect(poly.vertices.length, anyOf(equals(3), equals(4)));
        expect(poly.normal, isNotNull);
      }
    });

    test('WeldParts dynamically calculates contact seam and leg directions for arbitrary joints', () {
      final vm = AssemblyStudioViewModel();
      vm.loadStandardLadderDemo();

      // Add a test rung welded to right rail
      final rung = vm.doc.parts.firstWhere((p) => p.type == AssemblyPartType.rung);
      vm.weldParts('rail_right', rung.id);

      final newWeld = vm.doc.welds.last;
      expect(newWeld.weldAxis.x, equals(1.0));
      expect(newWeld.bothSides, isTrue);
      expect(newWeld.secondWeldPoint, isNotNull);
    });

    testWidgets('Horizontal and vertical camera panning tracks mouse drag direction and updates pan', (tester) async {
      final vm = AssemblyStudioViewModel();
      vm.loadStandardLadderDemo();
      expect(vm.pan, equals(Offset.zero));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 700,
              child: Assembly3DViewport(viewModel: vm),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final initAz = vm.azimuthDeg;
      final center = tester.getCenter(find.byType(Assembly3DViewport));

      // 1. Middle mouse button drag alone: Pans camera (direct middle mouse pan without Shift)
      final panGesture = await tester.startGesture(center, kind: PointerDeviceKind.mouse, buttons: kMiddleMouseButton);
      await panGesture.moveBy(const Offset(60, 40));
      await tester.pump();
      await panGesture.up();
      await tester.pumpAndSettle();
      expect(vm.pan.dx, equals(60.0));
      expect(vm.pan.dy, equals(40.0));

      // 2. Shift + Middle mouse drag: Rotates camera (Orbit)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      final orbitGesture = await tester.startGesture(center, kind: PointerDeviceKind.mouse, buttons: kMiddleMouseButton);
      await orbitGesture.moveBy(const Offset(60, 40));
      await tester.pump();
      await orbitGesture.up();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(vm.azimuthDeg, isNot(equals(initAz)));
    });

    test('Bounding Box 12 Edge Centers, Snapping & Hole Outline Boundaries', () {
      final vm = AssemblyStudioViewModel();
      expect(vm.doc.parts.isNotEmpty, isTrue);
      final rail = vm.doc.parts.first;

      // 1. 12 Bounding Box Edge Centers
      final edgeCenters = rail.getBoundingBoxEdgeCenterPoints();
      expect(edgeCenters.length, equals(12));

      // 2. Candidate point snapping snaps to bounding box edge center
      final targetEc = edgeCenters[0];
      Offset fakeProject(CadPoint3D pt) => Offset(pt.x, pt.y);
      final snapped = AssemblyRaycaster.snapToCandidatePoints(
        cursorPos: Offset(targetEc.x + 5.0, targetEc.y - 3.0),
        candidatePoints: edgeCenters,
        projectPoint: fakeProject,
        pixelTolerance: 16.0,
      );
      expect(snapped, isNotNull);
      expect(snapped!.x, closeTo(targetEc.x, 1e-4));
      expect(snapped.y, closeTo(targetEc.y, 1e-4));

      // 3. Mesh builder generates wireframe silhouette & hole boundaries for assembly
      final mesh = rail.build3DMesh();
      expect(mesh.allPolygons.any((p) => p.holes.isNotEmpty), isTrue);

      try {
        final node = FlutterSceneCadMeshBuilder.buildCadModel(
          mesh,
          renderMode: OnshapeRenderMode.shadedWithEdges,
          showWireframe: true,
        );
        expect(node, isNotNull);
        final edgeNode = node.children.where((n) => n.name == 'CadBoundaryEdges').firstOrNull;
        expect(edgeNode, isNotNull);
      } catch (e) {
        // Flutter GPU requires Impeller backend in native runtimes; in headless unit test it falls back gracefully
        expect(e.toString(), contains('Impeller'));
      }
    });

    test('Magnetic Tool: places snap spots, attracts parts, cluster moves together, allows rotation in place, and breaks links', () {
      final vm = AssemblyStudioViewModel();
      vm.loadStandardLadderDemo();

      final parts = vm.doc.parts;
      expect(parts.length, greaterThanOrEqualTo(2));
      final partA = parts[0];
      final partB = parts[1];

      // 1. Add magnetic spots to both parts
      final spotA = vm.addMagneticSpot(
        partA.id,
        const CadPoint3D(100.0, 50.0, 0.0),
        const CadPoint3D(0.0, 0.0, 1.0),
        name: 'Spot A',
      );
      expect(spotA, isNotNull);
      expect(vm.doc.parts.firstWhere((p) => p.id == partA.id).magneticSpots.length, 1);

      final spotB = vm.addMagneticSpot(
        partB.id,
        const CadPoint3D(20.0, 30.0, 0.0),
        const CadPoint3D(0.0, 0.0, -1.0),
        name: 'Spot B',
      );
      expect(spotB, isNotNull);
      expect(vm.doc.parts.firstWhere((p) => p.id == partB.id).magneticSpots.length, 1);

      // 2. Couple the spots with a magnetic joint (attracts part B to part A)
      final success = vm.createMagneticJoint(
        partAId: partA.id,
        spotAId: spotA!.id,
        partBId: partB.id,
        spotBId: spotB!.id,
      );
      expect(success, isTrue);
      expect(vm.doc.magneticJoints.length, 1);
      expect(vm.isPartMagneticallyLinked(partA.id), isTrue);
      expect(vm.isPartMagneticallyLinked(partB.id), isTrue);

      // 3. Cluster identification: partA and partB form a magnetic cluster
      final cluster = vm.getMagneticallyLinkedClusterPartIds(partA.id);
      expect(cluster.contains(partA.id), isTrue);
      expect(cluster.contains(partB.id), isTrue);

      // 4. Moving an entity moves the entire magnetic cluster together so they cannot be pulled apart
      final startPosA = vm.doc.parts.firstWhere((p) => p.id == partA.id).position;
      final startPosB = vm.doc.parts.firstWhere((p) => p.id == partB.id).position;
      vm.selectPart(partA.id);
      vm.nudgeSelectedPosition(50.0, 0.0, 0.0);

      final newPosA = vm.doc.parts.firstWhere((p) => p.id == partA.id).position;
      final newPosB = vm.doc.parts.firstWhere((p) => p.id == partB.id).position;
      expect(newPosA.x, closeTo(startPosA.x + 50.0, 0.001));
      expect(newPosB.x, closeTo(startPosB.x + 50.0, 0.001));

      // 5. Magnetically linked entity CAN rotate in place without breaking joint
      final rotBefore = vm.doc.parts.firstWhere((p) => p.id == partA.id).rotationDeg;
      vm.nudgeSelectedRotation(0.0, 0.0, 30.0);
      final rotAfter = vm.doc.parts.firstWhere((p) => p.id == partA.id).rotationDeg;
      expect(rotAfter.z, closeTo((rotBefore.z + 30.0) % 360.0, 0.001));
      expect(vm.doc.magneticJoints.length, 1); // Joint remains intact!

      // 6. Breaking magnetic joints
      vm.breakAllMagneticJointsForPart(partA.id);
      expect(vm.doc.magneticJoints.isEmpty, isTrue);
      expect(vm.isPartMagneticallyLinked(partA.id), isFalse);
      expect(vm.isPartMagneticallyLinked(partB.id), isFalse);
    });

    test('Weld Tool: seamless solid fillet weld bead generation has no interior wireframes', () {
      final vm = AssemblyStudioViewModel();
      vm.loadStandardLadderDemo();

      final mesh = vm.assemblyMesh;
      final weldPolys = mesh.polygons.where((p) => p.faceId.startsWith('weld_')).toList();
      expect(weldPolys.isNotEmpty, isTrue);

      // All weld polygons must have drawWireframe == false (seamless solid aesthetic matching AutoCAD SS2)
      for (final p in weldPolys) {
        expect(p.drawWireframe, isFalse);
      }
    });
  });
}




