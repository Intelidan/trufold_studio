// =============================================================================
// flutter_paint_3d_engine.dart
//
// 1st Generation Pure Flutter Canvas 2.5D CAD Projection & Shading Engine.
// Provides a zero-dependency, pure software 3D rendering pipeline:
// - Spherical turntable/trackball projection to 2D Canvas
// - Painter's depth sorting algorithm with normal shading
// - Accurate hole punch cutouts and chamfers
// - Real-time face/bend/punch hover and selection highlights
// - CMS physical port badges and terminal leader lines
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../models/cad_primitives.dart';
import '../../../../models/cms/cms_physical_port.dart';
import '../../../../engine/kinematic_fold_engine.dart';
import '../../../../engine/matrix4_math_helper.dart';

typedef _DrawFacet = ({
  Path fillPath,
  Path? strokePath,
  Path? holesPath,
  Path? selectedHolesPath,
  Path? clipBoundary,
  double depth,
  double minDepth,
  double maxDepth,
  Rect bounds,
  CadPoint3D camNormal,
  CadPoint3D p0Cam,
  Offset p0Screen,
  double p0Depth,
  Color color,
  List<List<Offset>> cuts,
  String faceId,
  bool isFillet,
  bool isBore,
  bool isHighlighted,
  List<Offset> prjVerts,
  List<CadPoint3D> camVerts,
});

class FlutterPaint3dPainter extends CustomPainter {
  final FoldedMeshResult mesh;
  final double azimuthDeg;
  final double elevationDeg;
  final double zoom;
  final Offset pan;
  final bool showWireframe;
  final bool isGlassMode;
  final bool isOrthoProjection;
  final bool isInteracting;
  final String? selectedBendId;
  final String? selectedPunchId;
  final String? selectedFaceId;
  final String? hoveredPunchId;
  final String? hoveredBendId;
  final String? hoveredFaceId;
  final List<CmsPhysicalPort> activePorts;
  final String? focusedPortId;
  final TransformMatrix4? modelTransform;

  FlutterPaint3dPainter({
    required this.mesh,
    required this.azimuthDeg,
    required this.elevationDeg,
    required this.zoom,
    required this.pan,
    required this.showWireframe,
    this.isGlassMode = false,
    this.isOrthoProjection = false,
    this.isInteracting = false,
    this.selectedBendId,
    this.selectedPunchId,
    this.selectedFaceId,
    this.hoveredPunchId,
    this.hoveredBendId,
    this.hoveredFaceId,
    this.activePorts = const [],
    this.focusedPortId,
    this.modelTransform,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || mesh.polygons.isEmpty) return;

    final cx = size.width / 2.0 + pan.dx;
    final cy = size.height / 2.0 + pan.dy;

    // View angles in radians (full 360° free roaming)
    final azRad = azimuthDeg * math.pi / 180.0;
    final elRad = elevationDeg * math.pi / 180.0;

    final cosAz = math.cos(azRad);
    final sinAz = math.sin(azRad);
    final cosEl = math.cos(elRad);
    final sinEl = math.sin(elRad);

    final List<double> m = modelTransform?.m ?? [
      cosAz, sinAz, 0.0, 0.0,
      -sinEl * sinAz, sinEl * cosAz, cosEl, 0.0,
      cosEl * sinAz, -cosEl * cosAz, sinEl, 0.0,
      0.0, 0.0, 0.0, 1.0,
    ];

    // Directional virtual light source
    const lightDir = CadPoint3D(0.577, 0.577, 0.577);

    // Compute automatic scaling
    final maxDim = math.max(mesh.boundWidth, math.max(mesh.boundLength, mesh.boundHeight));
    final fitDim = maxDim > 0 ? maxDim : 200.0;
    final baseScale = (math.min(size.width, size.height) * 0.60) / fitDim;
    final scale = baseScale * zoom;

    // Center pivot point
    final pivot = mesh.center;

    // Camera perspective distance: 2.5x the model extent gives a natural 3D CAD perspective
    final cameraDist = math.max(fitDim * 2.5, 1000.0);

    // Transform a 3D point to camera space and project to screen (Z-up turntable / trackball CAD coordinates)
    ({Offset pt, double depth, CadPoint3D camPt}) project(CadPoint3D p) {
      final rx = p.x - pivot.x;
      final ry = p.y - pivot.y;
      final rz = p.z - pivot.z;

      final x2 = rx * m[0] + ry * m[1] + rz * m[2];
      final y2 = rx * m[4] + ry * m[5] + rz * m[6];
      final z2 = rx * m[8] + ry * m[9] + rz * m[10];

      final persp = isOrthoProjection ? 1.0 : (cameraDist / math.max(cameraDist - z2, cameraDist * 0.15));

      final sx = cx + (x2 * persp) * scale;
      final sy = cy - (y2 * persp) * scale;

      return (pt: Offset(sx, sy), depth: z2, camPt: CadPoint3D(x2, y2, z2));
    }

    // List of drawable facets sorted by camera depth
    final drawList = <_DrawFacet>[];
    final addedWireframeEdgeKeys = <String>{};

    for (final poly in mesh.allPolygons) {
      if (poly.vertices.length < 3) continue;

      final isWeld = poly.faceId.startsWith('weld_');
      final isFillet = poly.faceId.startsWith('FILLET_');
      final isBore = poly.faceId.startsWith('BORE_') || poly.faceId.contains('_slot_') || poly.faceId.contains('_wall_');
      final isInner = poly.faceId.endsWith('_inner') || poly.faceId.endsWith('_BOT');
      final isRim = poly.faceId.startsWith('RIM_') || poly.faceId.startsWith('FILLET_CAP') || poly.faceId.startsWith('CHAMFER_');
      final isFaceSelected = (poly.faceId == selectedFaceId) ||
          (selectedFaceId != null && poly.faceId.startsWith(selectedFaceId!));
      final isFaceHovered = (poly.faceId == hoveredFaceId);
      final isBendHighlighted =
          (selectedBendId != null && poly.faceId.contains(selectedBendId!)) || (hoveredBendId != null && poly.faceId.contains(hoveredBendId!));
      final isPunchHighlighted =
          isBore && ((selectedPunchId != null && poly.faceId.contains(selectedPunchId!)) || (hoveredPunchId != null && poly.faceId.contains(hoveredPunchId!)));
      final isHighlighted = isFaceSelected || isFaceHovered || isBendHighlighted || isPunchHighlighted;

      final n = poly.normal;

      // Camera-space outward normal vector
      final nx2 = n.x * m[0] + n.y * m[1] + n.z * m[2];
      final ny2 = n.x * m[4] + n.y * m[5] + n.z * m[6];
      final nz2 = n.x * m[8] + n.y * m[9] + n.z * m[10];
      final camNormalZ = nz2;
      final polyCamNormal = CadPoint3D(nx2, ny2, nz2);

      // Back-face culling for welds: never render weld bead facets facing away from camera (prevents see-through)
      if (isWeld && camNormalZ <= 0.0) continue;

      // Solid/Glass Opaque Mode: Selective back-face culling
      // Thickness shell (RIM, CHAMFER, FILLET_CAP) is culled when back-facing in solid mode.
      if (mesh.thicknessPolygons.isNotEmpty) {
        final isRimOrChamfer = poly.faceId.startsWith('RIM_') || poly.faceId.startsWith('CHAMFER_') || poly.faceId.startsWith('FILLET_CAP');
        if (!isRimOrChamfer) {
          // In glass mode: _BOT face is suppressed — top face at alpha + opaque rim avoids hollow look
          if (isGlassMode && poly.faceId.endsWith('_BOT')) continue;
          // In glass mode: bore walls are inside holes — skip them (they show through transparent plate)
          if (isGlassMode && isBore) continue;

          // Solid mode: do NOT cull sheet metal faces — in open sheet metal assemblies,
          // both inner webs, outer webs, rungs, and flanges are visible.
          // Only cull hidden bore walls inside hole cylinders.
          if (!isGlassMode) {
            if (isBore && camNormalZ <= 0.0) continue;
          }
        } else {
          // In solid mode: back-facing thickness rims, chamfers, and fillet caps must be culled
          // so that back-edge strokes do not bleed through front surfaces.
          if (!isGlassMode && camNormalZ <= 0.0) continue;
        }
      }

      // Screen-space LOD for dense hole patterns (e.g. 3-meter perforations)
      if (isBore && mesh.allPolygons.length > 150) {
        final p0 = project(poly.vertices[0]).pt;
        final p1 = project(poly.vertices[1]).pt;
        final p2 = project(poly.vertices[2]).pt;
        final screenSpan = math.max((p1 - p0).distance, (p2 - p1).distance);
        if (screenSpan < 2.5) {
          continue; // Sub-pixel bore quad: skipped for silky-smooth 60 FPS performance
        }
      }

      // Dual-light CAD illumination (Key light + subtle Fill light) + Blinn-Phong specular glints:
      final dotLight = (n.x * lightDir.x + n.y * lightDir.y + n.z * lightDir.z).abs().clamp(0.0, 1.0);
      final fillDot = (n.x * (-0.3) + n.y * (-0.5) + n.z * 0.8).abs().clamp(0.0, 1.0);
      final diffuseFactor = 0.70 + 0.25 * dotLight + 0.10 * fillDot;

      // View direction towards screen: CadPoint3D(0, 0, 1)
      // Half-vector between lightDir (0.577, 0.577, 0.577) and viewDir (0, 0, 1)
      const halfDir = CadPoint3D(0.325, 0.325, 0.888);
      final dotHalf = (n.x * halfDir.x + n.y * halfDir.y + n.z * halfDir.z).abs().clamp(0.0, 1.0);
      final specular = math.pow(dotHalf, 18.0) * (isWeld ? 0.38 : 0.28);

      final baseColor = poly.color;
      Color shadedColor;
      if (isFaceSelected) {
        shadedColor = const Color(0xFF38BDF8).withValues(alpha: 0.90);
      } else if (isFaceHovered) {
        shadedColor = const Color(0xFFBAE6FD).withValues(alpha: 0.92);
      } else if (isBendHighlighted) {
        shadedColor = const Color(0xFFFDE68A).withValues(alpha: 0.92);
      } else if (isPunchHighlighted) {
        shadedColor = const Color(0xFF00E5FF).withValues(alpha: 0.95);
      } else {
        shadedColor = Color.from(
          alpha: 1.0,
          red: (baseColor.r * diffuseFactor + specular).clamp(0.0, 1.0),
          green: (baseColor.g * diffuseFactor + specular).clamp(0.0, 1.0),
          blue: (baseColor.b * diffuseFactor + specular).clamp(0.0, 1.0),
        );
      }

      // Project laser cut lines on this face
      final prjCuts = <List<Offset>>[];
      for (final seg in poly.cutSegments) {
        if (seg.length >= 2) {
          prjCuts.add(seg.map((cv) => project(cv).pt).toList());
        }
      }

      // Project full face boundary
      final prjVerts = poly.vertices.map((v) => project(v)).toList();
      double minD = prjVerts.first.depth;
      double maxD = prjVerts.first.depth;
      double minX = prjVerts.first.pt.dx;
      double maxX = prjVerts.first.pt.dx;
      double minY = prjVerts.first.pt.dy;
      double maxY = prjVerts.first.pt.dy;
      for (int i = 1; i < prjVerts.length; i++) {
        final p = prjVerts[i];
        if (p.depth < minD) minD = p.depth;
        if (p.depth > maxD) maxD = p.depth;
        if (p.pt.dx < minX) minX = p.pt.dx;
        if (p.pt.dx > maxX) maxX = p.pt.dx;
        if (p.pt.dy < minY) minY = p.pt.dy;
        if (p.pt.dy > maxY) maxY = p.pt.dy;
      }
      final polyBounds = Rect.fromLTRB(minX, minY, maxX, maxY);

      final outerPath = Path()..moveTo(prjVerts.first.pt.dx, prjVerts.first.pt.dy);
      for (int i = 1; i < prjVerts.length; i++) {
        outerPath.lineTo(prjVerts[i].pt.dx, prjVerts[i].pt.dy);
      }
      outerPath.close();

      // GPU Hardware Cutouts via evenOdd winding: zero CPU CSG calls!
      final faceFillPath = Path()..fillType = PathFillType.evenOdd;
      faceFillPath.addPath(outerPath, Offset.zero);

      final holePaths = <Path>[];
      final selectedHolesPath = Path();
      bool hasSelectedHoles = false;

      for (int hIdx = 0; hIdx < poly.holes.length; hIdx++) {
        final hole = poly.holes[hIdx];
        if (hole.length >= 3) {
          final hPts = hole.map((hv) => project(hv).pt).toList();
          final hPath = Path()..moveTo(hPts.first.dx, hPts.first.dy);
          for (int i = 1; i < hPts.length; i++) {
            hPath.lineTo(hPts[i].dx, hPts[i].dy);
          }
          hPath.close();
          holePaths.add(hPath);

          final punchId = hIdx < poly.holePunchIds.length ? poly.holePunchIds[hIdx] : null;
          if (punchId != null && (punchId == selectedPunchId || punchId == hoveredPunchId)) {
            selectedHolesPath.addPath(hPath, Offset.zero);
            hasSelectedHoles = true;
          }
        }
      }

      // SS2 Fix: Merge overlapping punch voids into unified compound outlines
      // During active mouse interaction, bypass expensive Path.combine CSG for smooth 60-120 FPS
      final List<Path> mergedHolePaths = isInteracting ? holePaths : _mergeOverlappingPaths(holePaths);

      final allHolesPath = Path();
      bool hasHoles = false;
      for (final hPath in mergedHolePaths) {
        faceFillPath.addPath(hPath, Offset.zero);
        allHolesPath.addPath(hPath, Offset.zero);
        hasHoles = true;
      }

      final sumDepth = prjVerts.fold(0.0, (acc, p) => acc + p.depth);
      var avgDepth = sumDepth / prjVerts.length;

      // Fix 1 & 2: Deterministic depth bias by face type so nearly coplanar faces always
      // sort in the correct category order regardless of camera rotation.
      // Categories (higher number = drawn later = in front):
      //   0 = _BOT plate face        (always behind)
      //   1 = FILLET_ inner surface  (concave, behind plate)
      //   2 = BORE_ bore walls       (inside hole)
      //   3 = Normal top plate face  (middle)
      //   4 = FILLET_OUT_ convex     (outside of bend)
      //   5 = RIM_/CHAMFER_/FILLET_CAP (always in front)
      final faceTypePriority = _facePriority(poly.faceId);
      // Apply a small categorical depth offset so two faces with identical projected depths
      // sort deterministically by category. Offset is 0.015 per priority level (small enough
      // not to visually displace faces relative to their true 3D positions).
      avgDepth += (faceTypePriority - 3) * 0.015;

      // Stroke boundaryLines if provided, or deduplicate outer boundary edges
      Path? strokePath;
      if (poly.boundaryLines.isNotEmpty) {
        strokePath = Path();
        for (final line in poly.boundaryLines) {
          if (line.length >= 2) {
            for (int i = 0; i < line.length - 1; i++) {
              final pA = line[i];
              final pB = line[i + 1];
              final kA = '${(pA.x * 5).round()}_${(pA.y * 5).round()}_${(pA.z * 5).round()}';
              final kB = '${(pB.x * 5).round()}_${(pB.y * 5).round()}_${(pB.z * 5).round()}';
              if (kA == kB) continue;
              final edgeKey = kA.compareTo(kB) <= 0 ? '$kA--$kB' : '$kB--$kA';
              if (!addedWireframeEdgeKeys.add(edgeKey)) continue;

              final prjA = project(pA).pt;
              final prjB = project(pB).pt;
              strokePath.moveTo(prjA.dx, prjA.dy);
              strokePath.lineTo(prjB.dx, prjB.dy);
            }
          }
        }
      } else if (isFillet || isBore || isInner || isRim || isWeld || !poly.drawWireframe) {
        // Suppress wireframe borders on curved fillets, bore hole walls, welds,
        // and internal / thickness shell faces.
        strokePath = null;
      } else if (showWireframe) {
        // Fallback for models without explicit boundaryLines: deduplicate outer perimeter edges
        strokePath = Path();
        for (int i = 0; i < poly.vertices.length; i++) {
          final pA = poly.vertices[i];
          final pB = poly.vertices[(i + 1) % poly.vertices.length];
          final kA = '${(pA.x * 5).round()}_${(pA.y * 5).round()}_${(pA.z * 5).round()}';
          final kB = '${(pB.x * 5).round()}_${(pB.y * 5).round()}_${(pB.z * 5).round()}';
          if (kA == kB) continue;
          final edgeKey = kA.compareTo(kB) <= 0 ? '$kA--$kB' : '$kB--$kA';
          if (!addedWireframeEdgeKeys.add(edgeKey)) continue;

          final prjA = project(pA).pt;
          final prjB = project(pB).pt;
          strokePath.moveTo(prjA.dx, prjA.dy);
          strokePath.lineTo(prjB.dx, prjB.dy);
        }

        // Holes / cutouts outline loops
        for (final hole in poly.holes) {
          if (hole.length >= 2) {
            for (int i = 0; i < hole.length; i++) {
              final pA = hole[i];
              final pB = hole[(i + 1) % hole.length];
              final kA = '${(pA.x * 5).round()}_${(pA.y * 5).round()}_${(pA.z * 5).round()}';
              final kB = '${(pB.x * 5).round()}_${(pB.y * 5).round()}_${(pB.z * 5).round()}';
              if (kA == kB) continue;
              final edgeKey = kA.compareTo(kB) <= 0 ? '$kA--$kB' : '$kB--$kA';
              if (!addedWireframeEdgeKeys.add(edgeKey)) continue;

              final prjA = project(pA).pt;
              final prjB = project(pB).pt;
              strokePath.moveTo(prjA.dx, prjA.dy);
              strokePath.lineTo(prjB.dx, prjB.dy);
            }
          }
        }
      }

      drawList.add((
        fillPath: faceFillPath,
        strokePath: strokePath,
        holesPath: hasHoles ? allHolesPath : null,
        selectedHolesPath: hasSelectedHoles ? selectedHolesPath : null,
        clipBoundary: hasHoles ? outerPath : null,
        depth: avgDepth,
        minDepth: minD,
        maxDepth: maxD,
        bounds: polyBounds,
        camNormal: polyCamNormal,
        p0Cam: prjVerts.first.camPt,
        p0Screen: prjVerts.first.pt,
        p0Depth: prjVerts.first.depth,
        color: shadedColor,
        cuts: prjCuts,
        faceId: poly.faceId,
        isFillet: isFillet,
        isBore: isBore,
        isHighlighted: isHighlighted,
        prjVerts: prjVerts.map((p) => p.pt).toList(),
        camVerts: prjVerts.map((p) => p.camPt).toList(),
      ));
    }

    // Add 3D Channel Mouth Aperture Port Facets to drawList so they participate in true 3D depth occlusion
    for (final port in activePorts) {
      List<CadPoint3D> corners = port.derivedMouthCorners;
      if (corners.length < 4 && port.width > 1.0 && port.height > 1.0) {
        final floorCenter = CadPoint3D(
          port.center.x - (port.height / 2.0) * port.heightDirection.x,
          port.center.y - (port.height / 2.0) * port.heightDirection.y,
          port.center.z - (port.height / 2.0) * port.heightDirection.z,
        );
        final p0 = CadPoint3D(
          floorCenter.x - (port.width / 2.0) * port.widthDirection.x,
          floorCenter.y - (port.width / 2.0) * port.widthDirection.y,
          floorCenter.z - (port.width / 2.0) * port.widthDirection.z,
        );
        final p3 = CadPoint3D(
          floorCenter.x + (port.width / 2.0) * port.widthDirection.x,
          floorCenter.y + (port.width / 2.0) * port.widthDirection.y,
          floorCenter.z + (port.width / 2.0) * port.widthDirection.z,
        );
        final p1 = CadPoint3D(
          p0.x + port.height * port.heightDirection.x,
          p0.y + port.height * port.heightDirection.y,
          p0.z + port.height * port.heightDirection.z,
        );
        final p2 = CadPoint3D(
          p3.x + port.height * port.heightDirection.x,
          p3.y + port.height * port.heightDirection.y,
          p3.z + port.height * port.heightDirection.z,
        );
        corners = [p0, p1, p2, p3];
      }

      if (corners.length >= 4) {
        final prjVerts = corners.map((v) => project(v)).toList();
        final p0 = prjVerts[0].pt;
        final p1 = prjVerts[1].pt;
        final p2 = prjVerts[2].pt;
        final p3 = prjVerts[3].pt;

        final mouthPath = Path()
          ..moveTo(p0.dx, p0.dy)
          ..lineTo(p1.dx, p1.dy)
          ..lineTo(p2.dx, p2.dy)
          ..lineTo(p3.dx, p3.dy)
          ..close();

        double minD = prjVerts.first.depth;
        double maxD = prjVerts.first.depth;
        double minX = prjVerts.first.pt.dx;
        double maxX = prjVerts.first.pt.dx;
        double minY = prjVerts.first.pt.dy;
        double maxY = prjVerts.first.pt.dy;
        for (int i = 1; i < prjVerts.length; i++) {
          final p = prjVerts[i];
          if (p.depth < minD) minD = p.depth;
          if (p.depth > maxD) maxD = p.depth;
          if (p.pt.dx < minX) minX = p.pt.dx;
          if (p.pt.dx > maxX) maxX = p.pt.dx;
          if (p.pt.dy < minY) minY = p.pt.dy;
          if (p.pt.dy > maxY) maxY = p.pt.dy;
        }
        final polyBounds = Rect.fromLTRB(minX, minY, maxX, maxY);

        // Compute 3D camera normal for exact depthAt evaluation
        CadPoint3D n = port.normal;
        if (n.x * n.x + n.y * n.y + n.z * n.z < 0.1 && corners.length >= 4) {
          final v1 = CadPoint3D(corners[1].x - corners[0].x, corners[1].y - corners[0].y, corners[1].z - corners[0].z);
          final v2 = CadPoint3D(corners[3].x - corners[0].x, corners[3].y - corners[0].y, corners[3].z - corners[0].z);
          final cx = v1.y * v2.z - v1.z * v2.y;
          final cy = v1.z * v2.x - v1.x * v2.z;
          final cz = v1.x * v2.y - v1.y * v2.x;
          final len = math.sqrt(cx * cx + cy * cy + cz * cz);
          if (len > 1e-4) n = CadPoint3D(cx / len, cy / len, cz / len);
        }
        final pCamX = n.x * m[0] + n.y * m[1] + n.z * m[2];
        final pCamY = n.x * m[4] + n.y * m[5] + n.z * m[6];
        final pCamZ = n.x * m[8] + n.y * m[9] + n.z * m[10];
        final polyCamNormal = CadPoint3D(pCamX, pCamY, pCamZ);

        final sumDepth = prjVerts.fold(0.0, (acc, p) => acc + p.depth);
        final avgDepth = sumDepth / prjVerts.length;

        final isFocused = port.id == focusedPortId;

        drawList.add((
          fillPath: mouthPath,
          strokePath: mouthPath,
          holesPath: null,
          selectedHolesPath: null,
          clipBoundary: null,
          depth: avgDepth,
          minDepth: minD,
          maxDepth: maxD,
          bounds: polyBounds,
          camNormal: polyCamNormal,
          p0Cam: prjVerts.first.camPt,
          p0Screen: prjVerts.first.pt,
          p0Depth: prjVerts.first.depth,
          color: isFocused ? const Color(0xFF00E5FF) : const Color(0xFF00E5FF),
          cuts: [
            [p0, p3],
          ], // Floor threshold edge
          faceId: 'PORT_MOUTH_${port.id}',
          isFillet: false,
          isBore: false,
          isHighlighted: isFocused,
          prjVerts: prjVerts.map((p) => p.pt).toList(),
          camVerts: prjVerts.map((p) => p.camPt).toList(),
        ));
      }
    }

    // Evaluates geometric depth order between two facets:
    // Returns < 0 if a should be drawn BEFORE b (a is behind b in 3D)
    // Returns > 0 if b should be drawn BEFORE a (b is behind a in 3D)
    int compareFacetDepth(_DrawFacet a, _DrawFacet b) {
      // 1. Strict 3D Depth Disjointness:
      if (a.maxDepth < b.minDepth - 1e-3) return -1;
      if (b.maxDepth < a.minDepth - 1e-3) return 1;

      // 2. Screen Bounding Box Disjointness:
      final overlap = a.bounds.intersect(b.bounds);
      if (overlap.width <= 0.5 || overlap.height <= 0.5) {
        final diff = a.depth - b.depth;
        if (diff.abs() > 0.01) return diff < 0 ? -1 : 1;
        return _facePriority(a.faceId).compareTo(_facePriority(b.faceId));
      }

      // 3. 3D Plane Half-Space Separation (Newell's Test):
      // Test A against plane of B (camera normal oriented towards camera: nz >= 0)
      CadPoint3D nB = b.camNormal;
      final lenB = math.sqrt(nB.x * nB.x + nB.y * nB.y + nB.z * nB.z);
      if (lenB > 1e-5) nB = CadPoint3D(nB.x / lenB, nB.y / lenB, nB.z / lenB);
      if (nB.z < 0) nB = CadPoint3D(-nB.x, -nB.y, -nB.z);

      bool allABehindB = true;
      bool allAInFrontB = true;
      for (final v in a.camVerts) {
        final dist = nB.x * (v.x - b.p0Cam.x) + nB.y * (v.y - b.p0Cam.y) + nB.z * (v.z - b.p0Cam.z);
        if (dist > 0.05) allABehindB = false;
        if (dist < -0.05) allAInFrontB = false;
      }
      if (allABehindB && !allAInFrontB) return -1;
      if (allAInFrontB && !allABehindB) return 1;

      // Test B against plane of A (camera normal oriented towards camera: nz >= 0)
      CadPoint3D nA = a.camNormal;
      final lenA = math.sqrt(nA.x * nA.x + nA.y * nA.y + nA.z * nA.z);
      if (lenA > 1e-5) nA = CadPoint3D(nA.x / lenA, nA.y / lenA, nA.z / lenA);
      if (nA.z < 0) nA = CadPoint3D(-nA.x, -nA.y, -nA.z);

      bool allBBehindA = true;
      bool allBInFrontA = true;
      for (final v in b.camVerts) {
        final dist = nA.x * (v.x - a.p0Cam.x) + nA.y * (v.y - a.p0Cam.y) + nA.z * (v.z - a.p0Cam.z);
        if (dist > 0.05) allBBehindA = false;
        if (dist < -0.05) allBInFrontA = false;
      }
      if (allBInFrontA && !allBBehindA) return -1;
      if (allBBehindA && !allBInFrontA) return 1;

      // 4. Centroid Depth & Category Priority (Instant O(1) vector math, zero Path ray-casting)
      final depthDiff = a.depth - b.depth;
      if (depthDiff.abs() > 0.01) return depthDiff < 0 ? -1 : 1;
      return _facePriority(a.faceId).compareTo(_facePriority(b.faceId));
    }

    // Step A: Baseline sort by average camera depth (Strict total order)
    drawList.sort((a, b) {
      final diff = a.depth - b.depth;
      if (diff.abs() > 0.01) return diff < 0 ? -1 : 1;
      return _facePriority(a.faceId).compareTo(_facePriority(b.faceId));
    });

    // Step B: Topological Newell Refinement Pass (High-Fidelity pass when not actively dragging)
    // Resolves any pair where depth-range overlap requires order reversal in Painter's algorithm
    if (!isInteracting) {
      final nFacets = drawList.length;
      int maxPasses = 3;
      while (maxPasses-- > 0) {
        bool anySwap = false;
        for (int i = 0; i < nFacets - 1; i++) {
          for (int j = i + 1; j < nFacets; j++) {
            final p = drawList[i];
            final q = drawList[j];
            if (q.minDepth > p.maxDepth + 0.1) break;

            final overlap = p.bounds.intersect(q.bounds);
            if (overlap.width <= 0.5 || overlap.height <= 0.5) continue;

            if (compareFacetDepth(q, p) < 0) {
              // q is behind p in 3D, so q must be drawn before p in Painter's algorithm
              drawList.removeAt(j);
              drawList.insert(i, q);
              anySwap = true;
              break;
            }
          }
        }
        if (!anySwap) break;
      }
    }

    // Render shaded faces with true cutout holes and crisp edges
    final facePaint = Paint()..style = PaintingStyle.fill;
    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = const Color(0xFF334155);

    final highlightEdgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..color = const Color(0xFF0284C7);

    final holeRimPaint = Paint()
      ..color = const Color(0xFF0F172A).withValues(alpha: 0.90)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final holeHighlightPaint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final cutLinePaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    // PASS 1: Render All Faces & Outlines Solid & Crisp
    // In glass mode, thickness-shell faces (RIM, CHAMFER, BORE, FILLET) are rendered opaque
    // and only the planar plate faces receive alpha transparency.
    bool isThicknessShell(String faceId) =>
        faceId.startsWith('RIM_') || faceId.startsWith('CHAMFER_') || faceId.startsWith('BORE_') || faceId.startsWith('FILLET_');

    // Fix 3: In glass mode, pre-render the opaque thickness shell first so it
    // always sits on top of the transparent plate surfaces.
    if (isGlassMode) {
      for (final item in drawList) {
        if (!isThicknessShell(item.faceId)) continue;
        if (!item.fillPath.getBounds().isEmpty && item.color.a > 0.0) {
          facePaint.color = item.color;
          canvas.drawPath(item.fillPath, facePaint);
        }
        if (item.strokePath != null && showWireframe) {
          canvas.drawPath(item.strokePath!, edgePaint);
        }
      }
    }

    for (final item in drawList) {
      // Fix 3: In glass mode, thickness-shell faces were already drawn opaque above.
      // Plate faces (top and _BOT) receive alpha-tinted glass colour; skip here
      // and draw them in Pass 2 below.
      if (isGlassMode && isThicknessShell(item.faceId)) continue;

      if (item.faceId.startsWith('PORT_MOUTH_')) {
        // Glowing thick border of port (no loud aperture wash; hidden behind front metal)
        final glowBorderPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5.2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = const Color(0xFF00E5FF).withValues(alpha: item.isHighlighted ? 0.55 : 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.2);
        canvas.drawPath(item.fillPath, glowBorderPaint);

        final coreBorderPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = item.isHighlighted ? 3.0 : 2.4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = const Color(0xFF00E5FF);
        canvas.drawPath(item.fillPath, coreBorderPaint);

        // Floor threshold marker line
        if (item.cuts.isNotEmpty && item.cuts.first.length >= 2) {
          final floorThresholdPaint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.0
            ..color = const Color(0xFF0284C7);
          canvas.drawLine(item.cuts.first[0], item.cuts.first[1], floorThresholdPaint);
        }
        continue;
      }

      if (!item.fillPath.getBounds().isEmpty && item.color.a > 0.0) {
        Color drawColor = item.color;
        final isWeld = item.faceId.startsWith('weld_');
        if (isGlassMode && !isWeld) {
          // Plate faces: render as translucent steel (welds remain solid opaque metal)
          drawColor = Color.from(alpha: 0.35, red: item.color.r, green: item.color.g, blue: item.color.b);
        }
        facePaint.color = drawColor;
        if (item.clipBoundary != null) {
          canvas.save();
          canvas.clipPath(item.clipBoundary!);
          canvas.drawPath(item.fillPath, facePaint);
          canvas.restore();
        } else {
          canvas.drawPath(item.fillPath, facePaint);
        }
      }

      if (item.strokePath != null) {
        if (item.isHighlighted) {
          canvas.drawPath(item.strokePath!, highlightEdgePaint);
        } else if (showWireframe) {
          canvas.drawPath(item.strokePath!, edgePaint);
        }
      }

      // Draw crisp hole rims strictly clipped to face boundary (no floating circles!)
      if (item.holesPath != null && !isGlassMode) {
        canvas.save();
        if (item.clipBoundary != null) {
          canvas.clipPath(item.clipBoundary!);
        } else if (item.strokePath != null) {
          canvas.clipPath(item.strokePath!);
        }
        canvas.drawPath(item.holesPath!, holeRimPaint);
        if (item.selectedHolesPath != null) {
          canvas.drawPath(item.selectedHolesPath!, holeHighlightPaint);
        }
        canvas.restore();
      }

      // Draw laser cut lines on the face surface
      for (final seg in item.cuts) {
        if (seg.length >= 2) {
          for (int i = 0; i < seg.length - 1; i++) {
            canvas.drawLine(seg[i], seg[i + 1], cutLinePaint);
          }
        }
      }
    }

    // PASS 2 (GLASS MODE): Render translucent X-Ray overlay showing back faces through front faces
    // Fix 3: Only plate panels participate in the occlusion detection, NOT the thickness shell.
    if (isGlassMode) {
      final glassOccludedPaint = Paint()
        ..color = const Color(0xFF0284C7).withValues(alpha: 0.22)
        ..style = PaintingStyle.fill;

      final glassHiddenEdgePaint = Paint()
        ..color = const Color(0xFF38BDF8).withValues(alpha: 0.70)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9;

      // Only compare plate faces (top and _BOT): skip the thickness shell entirely
      final panelItems = drawList.where((item) => !isThicknessShell(item.faceId)).toList();

      for (int i = 0; i < panelItems.length; i++) {
        final backItem = panelItems[i];
        if (backItem.fillPath.getBounds().isEmpty) continue;

        for (int j = i + 1; j < panelItems.length; j++) {
          final frontItem = panelItems[j];
          if (frontItem.fillPath.getBounds().isEmpty) continue;
          if (!backItem.fillPath.getBounds().overlaps(frontItem.fillPath.getBounds())) {
            continue;
          }

          // Compute exact region where back face was covered by front face
          try {
            final covered = Path.combine(PathOperation.intersect, backItem.fillPath, frontItem.fillPath);
            if (!covered.getBounds().isEmpty) {
              canvas.drawPath(covered, glassOccludedPaint);

              // Only draw the outer boundary stroke of the hidden back face
              // Do NOT draw holesPath — hole ghosts project as confusing flat shapes
              // when the back face is at 90° to the front face (bent flanges)
              canvas.save();
              canvas.clipPath(frontItem.fillPath);
              if (backItem.strokePath != null) {
                canvas.drawPath(backItem.strokePath!, glassHiddenEdgePaint);
              }
              canvas.restore();
            }
          } catch (_) {} // Graceful fallback if path combine fails
        }
      }
    }

    // PASS 3: Render Coplanar Port Tag Pill Callouts (visible over the body)
    for (final port in activePorts) {
      List<CadPoint3D> corners = port.derivedMouthCorners;
      if (corners.length < 4 && port.width > 1.0 && port.height > 1.0) {
        final floorCenter = CadPoint3D(
          port.center.x - (port.height / 2.0) * port.heightDirection.x,
          port.center.y - (port.height / 2.0) * port.heightDirection.y,
          port.center.z - (port.height / 2.0) * port.heightDirection.z,
        );
        final p0 = CadPoint3D(
          floorCenter.x - (port.width / 2.0) * port.widthDirection.x,
          floorCenter.y - (port.width / 2.0) * port.widthDirection.y,
          floorCenter.z - (port.width / 2.0) * port.widthDirection.z,
        );
        final p3 = CadPoint3D(
          floorCenter.x + (port.width / 2.0) * port.widthDirection.x,
          floorCenter.y + (port.width / 2.0) * port.widthDirection.y,
          floorCenter.z + (port.width / 2.0) * port.widthDirection.z,
        );
        final p1 = CadPoint3D(
          p0.x + port.height * port.heightDirection.x,
          p0.y + port.height * port.heightDirection.y,
          p0.z + port.height * port.heightDirection.z,
        );
        final p2 = CadPoint3D(
          p3.x + port.height * port.heightDirection.x,
          p3.y + port.height * port.heightDirection.y,
          p3.z + port.height * port.heightDirection.z,
        );
        corners = [p0, p1, p2, p3];
      }

      if (corners.length >= 4) {
        final p0 = project(corners[0]).pt;
        final p1 = project(corners[1]).pt;
        final p2 = project(corners[2]).pt;
        final p3 = project(corners[3]).pt;

        // --- Sleeping Coplanar Port Tag Pill (laying flat on the mouth plane) ---
        final faceCenter = Offset((p0.dx + p1.dx + p2.dx + p3.dx) / 4.0, (p0.dy + p1.dy + p2.dy + p3.dy) / 4.0);
        final vWidth = Offset((p3.dx - p0.dx + p2.dx - p1.dx) / 2.0, (p3.dy - p0.dy + p2.dy - p1.dy) / 2.0);
        var tagAngle = math.atan2(vWidth.dy, vWidth.dx);
        if (tagAngle > math.pi / 2.0) tagAngle -= math.pi;
        if (tagAngle < -math.pi / 2.0) tagAngle += math.pi;

        final isFocused = port.id == focusedPortId;
        const pillWidth = 114.0;
        const pillHeight = 32.0;
        final pillRRect = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: pillWidth, height: pillHeight), const Radius.circular(6.0));

        canvas.save();
        canvas.translate(faceCenter.dx, faceCenter.dy);
        canvas.rotate(tagAngle);

        // Ambient glow
        final glowPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0
          ..color = (isFocused ? const Color(0xFF00E5FF) : const Color(0xFF0284C7)).withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
        canvas.drawRRect(pillRRect, glowPaint);

        // Semi-translucent dark frosted pill body
        final pillFill = Paint()
          ..style = PaintingStyle.fill
          ..color = const Color(0xFF0F172A).withValues(alpha: 0.88);
        canvas.drawRRect(pillRRect, pillFill);

        // Crisp accent border
        final pillBorder = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isFocused ? 1.8 : 1.2
          ..color = isFocused ? const Color(0xFF00E5FF) : const Color(0xFF38BDF8).withValues(alpha: 0.8);
        canvas.drawRRect(pillRRect, pillBorder);

        // Status indicator dot
        final dotPaint = Paint()
          ..style = PaintingStyle.fill
          ..color = isFocused ? const Color(0xFF00E5FF) : const Color(0xFF34D399);
        canvas.drawCircle(const Offset(-pillWidth / 2.0 + 11.0, 0.0), 3.0, dotPaint);

        // Port ID (top line)
        final idSpan = TextSpan(
          text: port.id,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            color: isFocused ? const Color(0xFF00E5FF) : const Color(0xFF38BDF8),
            letterSpacing: 0.5,
          ),
        );
        final idPainter = TextPainter(text: idSpan, textDirection: TextDirection.ltr)..layout();
        idPainter.paint(canvas, Offset(-pillWidth / 2.0 + 20.0, -pillHeight / 2.0 + 4.0));

        // Dimensions (bottom line)
        final dimSpan = TextSpan(
          text: port.displayDimensions,
          style: const TextStyle(fontSize: 9.0, fontWeight: FontWeight.w700, color: Colors.white, fontFamily: 'monospace'),
        );
        final dimPainter = TextPainter(text: dimSpan, textDirection: TextDirection.ltr)..layout();
        dimPainter.paint(canvas, Offset(-pillWidth / 2.0 + 20.0, -pillHeight / 2.0 + 16.5));

        canvas.restore();
      }
    }
  }

  /// Face-type priority: determines draw order within the same depth band.
  /// Lower priority → drawn first (further back).
  /// Higher priority → drawn last (in front).
  static int _facePriority(String faceId) {
    // Thickness shell: always in front of plate faces
    if (faceId.startsWith('FILLET_CAP')) return 5;
    if (faceId.startsWith('CHAMFER_CAP')) return 5;
    if (faceId.startsWith('RIM_')) return 5;
    if (faceId.startsWith('CHAMFER_')) return 5;
    // Outer convex fillet surface
    if (faceId.startsWith('FILLET_OUT_')) return 4;
    // Pass-through weld projections on outside of rails
    if (faceId.contains('_proj_') || faceId.contains('_cap_')) return 4;
    // Standard plate face (including top plates, flanges, cover flaps, rails, rungs)
    if (!faceId.startsWith('FILLET_') && !faceId.startsWith('BORE_')) {
      return 3;
    }
    // Bore walls: inside holes
    if (faceId.startsWith('BORE_')) return 2;
    // Inner concave fillet: behind the plate
    if (faceId.startsWith('FILLET_')) return 1;
    if (faceId.startsWith('PORT_MOUTH_')) return 2;
    return 3;
  }

  static List<Path> _mergeOverlappingPaths(List<Path> paths) {
    if (paths.length <= 1) return paths;

    // Fast check: do any path bounds actually overlap before executing expensive Path.combine CSG?
    final bounds = paths.map((p) => p.getBounds()).toList();
    bool anyOverlap = false;
    for (int i = 0; i < bounds.length - 1; i++) {
      for (int j = i + 1; j < bounds.length; j++) {
        if (bounds[i].overlaps(bounds[j])) {
          anyOverlap = true;
          break;
        }
      }
      if (anyOverlap) break;
    }
    if (!anyOverlap) return paths;
    var current = List<Path>.of(paths);
    bool changed = true;
    int safetyCounter = 0;
    while (changed && safetyCounter++ < 10) {
      changed = false;
      final next = <Path>[];
      for (int i = 0; i < current.length; i++) {
        var p = current[i];
        if (p.getBounds().isEmpty) continue;
        for (int j = i + 1; j < current.length; j++) {
          final other = current[j];
          if (other.getBounds().isEmpty) continue;
          if (p.getBounds().overlaps(other.getBounds())) {
            try {
              final union = Path.combine(PathOperation.union, p, other);
              if (!union.getBounds().isEmpty) {
                p = union;
                current[j] = Path(); // Mark consumed
                changed = true;
              }
            } catch (_) {}
          }
        }
        next.add(p);
      }
      current = next.where((p) => !p.getBounds().isEmpty).toList();
    }
    return current;
  }

  @override
  bool shouldRepaint(covariant FlutterPaint3dPainter oldDelegate) {
    return oldDelegate.mesh != mesh ||
        oldDelegate.azimuthDeg != azimuthDeg ||
        oldDelegate.elevationDeg != elevationDeg ||
        oldDelegate.modelTransform != modelTransform ||
        oldDelegate.zoom != zoom ||
        oldDelegate.pan != pan ||
        oldDelegate.showWireframe != showWireframe ||
        oldDelegate.isGlassMode != isGlassMode ||
        oldDelegate.isOrthoProjection != isOrthoProjection ||
        oldDelegate.selectedBendId != selectedBendId ||
        oldDelegate.selectedPunchId != selectedPunchId ||
        oldDelegate.selectedFaceId != selectedFaceId ||
        oldDelegate.hoveredPunchId != hoveredPunchId ||
        oldDelegate.hoveredBendId != hoveredBendId ||
        oldDelegate.hoveredFaceId != hoveredFaceId ||
        oldDelegate.activePorts != activePorts ||
        oldDelegate.focusedPortId != focusedPortId;
  }
}
