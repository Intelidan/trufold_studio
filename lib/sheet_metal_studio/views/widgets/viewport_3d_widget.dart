// =============================================================================
// viewport_3d_widget.dart
//
// High-Performance 3D Shaded Viewport for truFold Studio by Danish.
// Features:
// - Light CAD Studio Theme with directional diffuse metallic shading
// - Enforced ClipRect preventing any 3D drawing spillover
// - True 3D punch hole cutouts (PathFillType.evenOdd) with crisp laser rims
// - Mouse wheel zoom (PointerScrollEvent)
// - Middle-mouse button camera panning (and Shift+Left drag fallback)
// - Turntable orbit controls and empty area click-to-deselect
// - Preset view alignment (ISO, TOP, FRONT, SIDE) and wireframe overlay
// Designed with ZERO external dependencies for 100% standalone portability.
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/cad_primitives.dart';
import '../../models/cms/cms_physical_port.dart';
import '../../viewmodels/sheet_metal_studio_viewmodel.dart';
import '../../engine/kinematic_fold_engine.dart';
import 'studio/studio_view_cube.dart';
import 'guided_cms/cms_3d_opening_callout.dart';

class Viewport3dWidget extends StatelessWidget {
  final SheetMetalStudioViewModel viewModel;

  const Viewport3dWidget({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFF8FAFC), Color(0xFFE2E8F0)],
              ),
            ),
            child: Stack(
              children: [
            // 1. Interactive Orbit, Middle-Mouse Pan & Wheel Zoom Surface
            Listener(
              onPointerSignal: (pointerSignal) {
                if (pointerSignal is PointerScrollEvent) {
                  final factor = pointerSignal.scrollDelta.dy < 0 ? 1.12 : 0.89;
                  viewModel.zoom3D(factor);
                }
              },
              onPointerMove: (event) {
                final isMiddleMouse = (event.buttons & kTertiaryButton) != 0;
                bool isShiftHeld = false;
                try {
                  isShiftHeld = HardwareKeyboard.instance.isShiftPressed;
                } catch (_) {}

                if (isMiddleMouse ||
                    (isShiftHeld &&
                        (event.buttons & kPrimaryMouseButton) != 0)) {
                  // Middle mouse or Shift+Left drag -> Pan 3D camera
                  viewModel.pan3DCanvas(event.delta);
                } else if ((event.buttons & kPrimaryMouseButton) != 0) {
                  // Left mouse drag -> Orbit turntable
                  viewModel.orbit3D(
                    event.delta.dx * 0.5,
                    -event.delta.dy * 0.5,
                  );
                }
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => viewModel.clearSelection(),
                child: ExcludeSemantics(
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _Viewport3dPainter(
                      mesh: viewModel.currentMesh,
                      azimuthDeg: viewModel.azimuthDeg,
                      elevationDeg: viewModel.elevationDeg,
                      zoom: viewModel.cameraZoom,
                      pan: viewModel.pan3D,
                      showWireframe: viewModel.showWireframe,
                      isGlassMode: viewModel.isGlassMode,
                      selectedBendId: viewModel.selectedBendId,
                      selectedPunchId: viewModel.selectedPunchId,
                      selectedFaceId: viewModel.selectedFaceId,
                      hoveredPunchId: viewModel.hoveredPunchId,
                      hoveredBendId: viewModel.hoveredBendId,
                      hoveredFaceId: viewModel.hoveredFaceId,
                      activePorts: viewModel.activeCmsPorts,
                    ),
                  ),
                ),
              ),
            ),

            // 2. Viewport Header Overlay (Light CAD Card)
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.view_in_ar, size: 14, color: Color(0xFF0284C7)),
                    SizedBox(width: 6),
                    Text(
                      '3D FOLDED MESH',
                      style: TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 3. Preset View & Display Buttons (ISO, TOP, FRONT, SIDE, GLASS, WIREFRAME, RESET)
            Positioned(
              top: 12,
              right: 90,
              left: 160,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Align(
                    alignment: Alignment.topRight,
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: math.max(100.0, constraints.maxWidth),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ScrollConfiguration(
                        behavior: ScrollConfiguration.of(context).copyWith(
                          dragDevices: {
                            PointerDeviceKind.touch,
                            PointerDeviceKind.mouse,
                            PointerDeviceKind.trackpad,
                            PointerDeviceKind.stylus,
                          },
                        ),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _cameraButton(
                                'ISO',
                                () => viewModel.setPresetView(
                                  azimuth: 45,
                                  elevation: 30,
                                ),
                              ),
                              _cameraButton(
                                'TOP',
                                () => viewModel.setPresetView(
                                  azimuth: 0,
                                  elevation: 89,
                                ),
                              ),
                              _cameraButton(
                                'FRONT',
                                () => viewModel.setPresetView(
                                  azimuth: 0,
                                  elevation: 0,
                                ),
                              ),
                              _cameraButton(
                                'SIDE',
                                () => viewModel.setPresetView(
                                  azimuth: 90,
                                  elevation: 0,
                                ),
                              ),
                              _modeButton(
                                label: viewModel.currentEdgeChamfer > 0
                                    ? 'CHAMFER ${viewModel.currentEdgeChamfer.toStringAsFixed(1)}mm'
                                    : 'CHAMFER',
                                isActive: viewModel.currentEdgeChamfer > 0,
                                icon: Icons.change_history,
                                tooltip:
                                    'Sheet Edge Chamfer (Bevel / Weld Prep)',
                                onTap: () => _showChamferDialog(context),
                              ),
                              _modeButton(
                                label: 'GLASS',
                                isActive: viewModel.isGlassMode,
                                icon: Icons.opacity,
                                tooltip:
                                    'Toggle Glass / X-Ray Mode (See Back Part)',
                                onTap: viewModel.toggleGlassMode,
                              ),
                              if (viewModel.activeCmsPorts.isNotEmpty)
                                _modeButton(
                                  label: 'PORTS',
                                  isActive: viewModel.showCmsPortHighlights,
                                  icon: Icons.tag,
                                  tooltip: 'Toggle 3D Channel Port Callouts & Highlights',
                                  onTap: viewModel.toggleCmsPortHighlights,
                                ),
                              IconButton(
                                icon: Icon(
                                  viewModel.showWireframe
                                      ? Icons.grid_on
                                      : Icons.grid_off,
                                  size: 14,
                                  color: viewModel.showWireframe
                                      ? const Color(0xFF0284C7)
                                      : const Color(0xFF64748B),
                                ),
                                tooltip: 'Toggle Wireframe',
                                onPressed: viewModel.toggleWireframe,
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.refresh,
                                  size: 14,
                                  color: Color(0xFF64748B),
                                ),
                                tooltip: 'Reset Camera',
                                onPressed: viewModel.resetCamera,
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // 3b. Interactive 3D ViewCube (Top Right 3D Orientation Marker)
            Positioned(
              top: 12,
              right: 12,
              child: StudioViewCube(
                azimuthDeg: viewModel.azimuthDeg,
                elevationDeg: viewModel.elevationDeg,
                onResetView: viewModel.resetCamera,
                onOrbit: (dAz, dEl) => viewModel.orbit3D(dAz, dEl),
                onSetView: (azimuth, elevation) {
                  viewModel.setPresetView(azimuth: azimuth, elevation: elevation);
                },
              ),
            ),

            // 4. Live 3D Dimensions Pill
            Positioned(
              bottom: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 3,
                    ),
                  ],
                ),
                child: Text(
                  '3D Bounding: ${viewModel.currentMesh.boundWidth.toStringAsFixed(0)} x ${viewModel.currentMesh.boundLength.toStringAsFixed(0)} x ${viewModel.currentMesh.boundHeight.toStringAsFixed(0)} mm',
                  style: const TextStyle(
                    color: Color(0xFF0284C7),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),

            // 5. 3D Opening Callouts for Discovered & Verified CMS Ports
            AnimatedBuilder(
              animation: Listenable.merge([viewModel, viewModel.cmsGuidedController]),
              builder: (context, _) {
                final ports = viewModel.activeCmsPorts;
                final mesh = viewModel.currentMesh;
                if (ports.isEmpty || size.width <= 0 || size.height <= 0 || mesh.polygons.isEmpty) {
                  return const SizedBox.shrink();
                }

                final cx = size.width / 2.0 + viewModel.pan3D.dx;
                final cy = size.height / 2.0 + viewModel.pan3D.dy;
                final azRad = viewModel.azimuthDeg * math.pi / 180.0;
                final elRad = viewModel.elevationDeg * math.pi / 180.0;
                final cosAz = math.cos(azRad);
                final sinAz = math.sin(azRad);
                final cosEl = math.cos(elRad);
                final sinEl = math.sin(elRad);
                final maxDim = math.max(mesh.boundWidth, math.max(mesh.boundLength, mesh.boundHeight));
                final fitDim = maxDim > 0 ? maxDim : 200.0;
                final baseScale = (math.min(size.width, size.height) * 0.60) / fitDim;
                final scale = baseScale * viewModel.cameraZoom;
                final pivot = mesh.center;

                return Stack(
                  children: ports.map((port) {
                    final anchor = port.calloutAnchor ?? port.center;
                    final rx = anchor.x - pivot.x;
                    final ry = anchor.y - pivot.y;
                    final rz = anchor.z - pivot.z;
                    final x1 = rx * cosAz - ry * sinAz;
                    final y1 = rx * sinAz + ry * cosAz;
                    final z1 = rz;
                    final x2 = x1;
                    final y2 = y1 * cosEl - z1 * sinEl;
                    final sx = cx + x2 * scale;
                    final sy = cy - y2 * scale;
                    final isFocused = port.id == viewModel.cmsGuidedController.state.focus.activePortId;

                    return Cms3DOpeningCallout(
                      port: port,
                      anchorScreenPosition: Offset(sx, sy),
                      isFocused: isFocused,
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      );
    },
    ),
    );
  }

  void _showChamferDialog(BuildContext context) {
    final currentChamfer = viewModel.currentEdgeChamfer;
    const presets = [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0];
    final controller = TextEditingController(
      text: currentChamfer > 0 ? currentChamfer.toStringAsFixed(1) : '1.0',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.change_history, color: Color(0xFF0284C7), size: 20),
            SizedBox(width: 8),
            Text(
              '3D Sheet Edge Chamfer (Weld Prep)',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Apply 45° beveled edge chamfers to the 3D sheet model. Essential for thick sheets (edge deburring, safety, and weld V-grooves). Settings are stored in the .dsf file.',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: presets.map((ch) {
                  final isSelected = (ch - currentChamfer).abs() < 1e-3;
                  return ChoiceChip(
                    label: Text(
                      ch == 0 ? 'None (Sharp)' : '${ch.toStringAsFixed(1)} mm',
                    ),
                    selected: isSelected,
                    selectedColor: const Color(0xFFE0F2FE),
                    labelStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: isSelected
                          ? const Color(0xFF0284C7)
                          : const Color(0xFF334155),
                    ),
                    onSelected: (_) {
                      viewModel.setGlobalEdgeChamfer(ch);
                      Navigator.of(ctx).pop();
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Custom Chamfer Width (mm)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (viewModel.edgeChamfers.isNotEmpty || currentChamfer > 0)
            TextButton(
              onPressed: () {
                viewModel.setGlobalEdgeChamfer(0.0);
                for (final k in viewModel.edgeChamfers.keys.toList()) {
                  viewModel.setEdgeChamfer(k, 0.0);
                }
                Navigator.of(ctx).pop();
              },
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFEF4444),
              ),
              child: const Text('Clear All'),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final val = double.tryParse(controller.text);
              if (val != null && val >= 0) {
                viewModel.setGlobalEdgeChamfer(val);
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  Widget _cameraButton(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFF334155),
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _modeButton({
    required String label,
    required bool isActive,
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFFE0F2FE) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isActive
                  ? const Color(0xFF0284C7)
                  : const Color(0xFFCBD5E1),
              width: isActive ? 1.2 : 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 13,
                color: isActive
                    ? const Color(0xFF0284C7)
                    : const Color(0xFF475569),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: isActive
                      ? const Color(0xFF0284C7)
                      : const Color(0xFF334155),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Viewport3dPainter extends CustomPainter {
  final FoldedMeshResult mesh;
  final double azimuthDeg;
  final double elevationDeg;
  final double zoom;
  final Offset pan;
  final bool showWireframe;
  final bool isGlassMode;
  final String? selectedBendId;
  final String? selectedPunchId;
  final String? selectedFaceId;
  final String? hoveredPunchId;
  final String? hoveredBendId;
  final String? hoveredFaceId;
  final List<CmsPhysicalPort> activePorts;

  _Viewport3dPainter({
    required this.mesh,
    required this.azimuthDeg,
    required this.elevationDeg,
    required this.zoom,
    required this.pan,
    required this.showWireframe,
    this.isGlassMode = false,
    this.selectedBendId,
    this.selectedPunchId,
    this.selectedFaceId,
    this.hoveredPunchId,
    this.hoveredBendId,
    this.hoveredFaceId,
    this.activePorts = const [],
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

    // Directional virtual light source
    const lightDir = CadPoint3D(0.577, 0.577, 0.577);

    // Compute automatic scaling
    final maxDim = math.max(
      mesh.boundWidth,
      math.max(mesh.boundLength, mesh.boundHeight),
    );
    final fitDim = maxDim > 0 ? maxDim : 200.0;
    final baseScale = (math.min(size.width, size.height) * 0.60) / fitDim;
    final scale = baseScale * zoom;

    // Center pivot point
    final pivot = mesh.center;

    // Transform a 3D point to camera space and project to screen
    ({Offset pt, double depth}) project(CadPoint3D p) {
      final rx = p.x - pivot.x;
      final ry = p.y - pivot.y;
      final rz = p.z - pivot.z;

      final x1 = rx * cosAz - ry * sinAz;
      final y1 = rx * sinAz + ry * cosAz;
      final z1 = rz;

      final x2 = x1;
      final y2 = y1 * cosEl - z1 * sinEl;
      final z2 = y1 * sinEl + z1 * cosEl;

      final sx = cx + x2 * scale;
      final sy = cy - y2 * scale;

      return (pt: Offset(sx, sy), depth: z2);
    }

    // List of drawable facets sorted by camera depth
    final drawList =
        <
          ({
            Path fillPath,
            Path? strokePath,
            Path? holesPath,
            Path? selectedHolesPath,
            Path? clipBoundary,
            double depth,
            Color color,
            List<List<Offset>> cuts,
            String faceId,
            bool isFillet,
            bool isBore,
            bool isHighlighted,
          })
        >[];

    for (final poly in mesh.allPolygons) {
      if (poly.vertices.length < 3) continue;

      final isFillet = poly.faceId.startsWith('FILLET_');
      final isBore = poly.faceId.startsWith('BORE_');
      final isFaceSelected = (poly.faceId == selectedFaceId);
      final isFaceHovered = (poly.faceId == hoveredFaceId);
      final isBendHighlighted =
          (selectedBendId != null && poly.faceId.contains(selectedBendId!)) ||
          (hoveredBendId != null && poly.faceId.contains(hoveredBendId!));
      final isPunchHighlighted = isBore &&
          ((selectedPunchId != null && poly.faceId.contains(selectedPunchId!)) ||
           (hoveredPunchId != null && poly.faceId.contains(hoveredPunchId!)));
      final isHighlighted =
          isFaceSelected || isFaceHovered || isBendHighlighted || isPunchHighlighted;

      final n = poly.normal;

      // Camera-space outward normal Z component (dot product with view direction)
      final camNormalZ = (n.x * sinAz + n.y * cosAz) * sinEl + n.z * cosEl;

      // Solid/Glass Opaque Mode: Selective back-face culling
      // Never cull rims, chamfers, or annular fillet caps (boundary shell).
      if (mesh.thicknessPolygons.isNotEmpty) {
        final isRimOrChamfer =
            poly.faceId.startsWith('RIM_') ||
            poly.faceId.startsWith('CHAMFER_') ||
            poly.faceId.startsWith('FILLET_CAP');
        if (!isRimOrChamfer) {
          // In glass mode: _BOT face is suppressed — top face at alpha + opaque rim avoids hollow look
          if (isGlassMode && poly.faceId.endsWith('_BOT')) continue;
          // In glass mode: bore walls are inside holes — skip them (they show through transparent plate)
          if (isGlassMode && isBore) continue;

          // Solid mode back-face culling
          if (!isGlassMode) {
            // Bottom face of sheet metal when viewing from above
            if (poly.faceId.endsWith('_BOT') && camNormalZ <= 0.0) continue;
            // Top face of sheet metal when viewing from below
            if (!poly.faceId.endsWith('_BOT') &&
                !isFillet &&
                !isBore &&
                camNormalZ <= 0.0) {
              continue;
            }
            // Curved bend fillet inside/outside
            if (poly.faceId.startsWith('FILLET_OUT_') && camNormalZ <= -0.1) {
              continue;
            }
            if (poly.faceId.startsWith('FILLET_') &&
                !poly.faceId.startsWith('FILLET_OUT_') &&
                camNormalZ <= -0.1) {
              continue;
            }
            // Bore walls: only show when mostly facing the camera (tight culling)
            // This prevents bore walls from being visible from outside looking at the flat face
            if (isBore && camNormalZ <= 0.0) continue;
          }
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

      // Diffuse CAD lighting with two-sided fallback
      final dotLight = (n.x * lightDir.x + n.y * lightDir.y + n.z * lightDir.z)
          .clamp(-1.0, 1.0);
      final lightFactor = dotLight > 0
          ? (0.65 + 0.35 * dotLight)
          : (0.45 + 0.20 * (-dotLight));

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
          red: (baseColor.r * lightFactor).clamp(0.0, 1.0),
          green: (baseColor.g * lightFactor).clamp(0.0, 1.0),
          blue: (baseColor.b * lightFactor).clamp(0.0, 1.0),
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
      final outerPath = Path()
        ..moveTo(prjVerts.first.pt.dx, prjVerts.first.pt.dy);
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
          if (punchId != null &&
              (punchId == selectedPunchId || punchId == hoveredPunchId)) {
            selectedHolesPath.addPath(hPath, Offset.zero);
            hasSelectedHoles = true;
          }
        }
      }

      // SS2 Fix: Merge overlapping punch voids into unified compound outlines
      // Eliminates odd-winding solid metal island in intersection
      final mergedHolePaths = _mergeOverlappingPaths(holePaths);

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

      // SS1 Fix: Stroke boundaryLines if provided (excludes bend seams and cuts across holes)
      Path? strokePath;
      if (poly.boundaryLines.isNotEmpty) {
        strokePath = Path();
        for (final line in poly.boundaryLines) {
          if (line.length >= 2) {
            final p0 = project(line[0]).pt;
            strokePath.moveTo(p0.dx, p0.dy);
            for (int i = 1; i < line.length; i++) {
              final pi = project(line[i]).pt;
              strokePath.lineTo(pi.dx, pi.dy);
            }
          }
        }
      } else if (isFillet) {
        // Fix 4: Suppress fillet facet subdivision strokes in solid mode.
        // Cylindrical bend surfaces look smooth and realistic without seam lines.
        strokePath = showWireframe ? outerPath : null;
      } else if (isBore) {
        strokePath = showWireframe ? outerPath : null;
      } else {
        strokePath = outerPath;
      }

      drawList.add((
        fillPath: faceFillPath,
        strokePath: strokePath,
        holesPath: hasHoles ? allHolesPath : null,
        selectedHolesPath: hasSelectedHoles ? selectedHolesPath : null,
        clipBoundary: hasHoles ? outerPath : null,
        depth: avgDepth,
        color: shadedColor,
        cuts: prjCuts,
        faceId: poly.faceId,
        isFillet: isFillet,
        isBore: isBore,
        isHighlighted: isHighlighted,
      ));
    }

    // Sort from back to front (Painter's Algorithm) with deterministic category tiebreaker
    drawList.sort((a, b) {
      final depthDiff = a.depth - b.depth;
      // When depths differ by more than the max categorical bias, use true 3D depth
      if (depthDiff.abs() > 0.01) return depthDiff < 0 ? -1 : 1;
      // Within the same depth band: sort by face category priority (back → front)
      final pa = _facePriority(a.faceId);
      final pb = _facePriority(b.faceId);
      return pa.compareTo(pb);
    });

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
        faceId.startsWith('RIM_') ||
        faceId.startsWith('CHAMFER_') ||
        faceId.startsWith('BORE_') ||
        faceId.startsWith('FILLET_');

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

      if (!item.fillPath.getBounds().isEmpty && item.color.a > 0.0) {
        Color drawColor = item.color;
        if (isGlassMode) {
          // Plate faces: render as translucent steel
          drawColor = Color.from(
            alpha: 0.35,
            red: item.color.r,
            green: item.color.g,
            blue: item.color.b,
          );
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
        } else if (showWireframe || (!item.isFillet && !item.isBore)) {
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
      final panelItems = drawList
          .where((item) => !isThicknessShell(item.faceId))
          .toList();

      for (int i = 0; i < panelItems.length; i++) {
        final backItem = panelItems[i];
        if (backItem.fillPath.getBounds().isEmpty) continue;

        for (int j = i + 1; j < panelItems.length; j++) {
          final frontItem = panelItems[j];
          if (frontItem.fillPath.getBounds().isEmpty) continue;
          if (!backItem.fillPath.getBounds().overlaps(
            frontItem.fillPath.getBounds(),
          )) {
            continue;
          }

          // Compute exact region where back face was covered by front face
          try {
            final covered = Path.combine(
              PathOperation.intersect,
              backItem.fillPath,
              frontItem.fillPath,
            );
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

    // PASS 3: Render 3D Channel Mouth Aperture Perimeter Highlight Loops
    for (final port in activePorts) {
      if (port.derivedMouthCorners.length >= 4) {
        final p0 = project(port.derivedMouthCorners[0]).pt;
        final p1 = project(port.derivedMouthCorners[1]).pt;
        final p2 = project(port.derivedMouthCorners[2]).pt;
        final p3 = project(port.derivedMouthCorners[3]).pt;

        final mouthPath = Path()
          ..moveTo(p0.dx, p0.dy)
          ..lineTo(p1.dx, p1.dy)
          ..lineTo(p2.dx, p2.dy)
          ..lineTo(p3.dx, p3.dy)
          ..close();

        // High-visibility cyan aperture wash
        final fillPaint = Paint()
          ..style = PaintingStyle.fill
          ..color = const Color(0xFF00E5FF).withValues(alpha: 0.18);
        canvas.drawPath(mouthPath, fillPaint);

        // Vibrant glowing border line loop (P1 -> P3 -> P4 -> P2 -> P1)
        final borderPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = const Color(0xFF00E5FF);
        canvas.drawPath(mouthPath, borderPaint);

        // Floor threshold marker line (P1 -> P2)
        final floorThresholdPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0
          ..color = const Color(0xFF0284C7);
        canvas.drawLine(p0, p3, floorThresholdPaint);
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
    // Standard top plate face
    if (!faceId.endsWith('_BOT') &&
        !faceId.startsWith('FILLET_') &&
        !faceId.startsWith('BORE_')) {
      return 3;
    }
    // Bore walls: behind rim but in front of bottom plate
    if (faceId.startsWith('BORE_')) return 2;
    // Inner concave fillet: behind the top plate
    if (faceId.startsWith('FILLET_')) return 1;
    // Bottom plate face: always behind
    if (faceId.endsWith('_BOT')) return 0;
    return 3;
  }

  static List<Path> _mergeOverlappingPaths(List<Path> paths) {
    if (paths.length <= 1) return paths;
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
  bool shouldRepaint(covariant _Viewport3dPainter oldDelegate) {
    return oldDelegate.mesh != mesh ||
        oldDelegate.azimuthDeg != azimuthDeg ||
        oldDelegate.elevationDeg != elevationDeg ||
        oldDelegate.zoom != zoom ||
        oldDelegate.pan != pan ||
        oldDelegate.showWireframe != showWireframe ||
        oldDelegate.isGlassMode != isGlassMode ||
        oldDelegate.selectedBendId != selectedBendId ||
        oldDelegate.selectedPunchId != selectedPunchId ||
        oldDelegate.selectedFaceId != selectedFaceId ||
        oldDelegate.hoveredPunchId != hoveredPunchId ||
        oldDelegate.hoveredBendId != hoveredBendId ||
        oldDelegate.hoveredFaceId != hoveredFaceId ||
        oldDelegate.activePorts != activePorts;
  }
}
