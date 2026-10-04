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

import '../../../models/cad_primitives.dart';
import '../../../models/cms/cms_physical_port.dart';
import '../../../models/trunking_cover_data.dart';
import '../../../viewmodels/sheet_metal_studio_viewmodel.dart';
import '../../../engine/kinematic_fold_engine.dart';
import '../studio/studio_view_cube.dart';

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

class LegacyViewport3dWidget extends StatefulWidget {
  final SheetMetalStudioViewModel viewModel;
  final bool isInteractionLocked;

  const LegacyViewport3dWidget({super.key, required this.viewModel, this.isInteractionLocked = false});

  @override
  State<LegacyViewport3dWidget> createState() => _LegacyViewport3dWidgetState();
}

class _LegacyViewport3dWidgetState extends State<LegacyViewport3dWidget> {
  SheetMetalStudioViewModel get viewModel => widget.viewModel;

  bool _isDraggingCover = false;
  bool _isHoveringCover = false;
  bool _pureVerticalDrag = false;
  double _lastPanZoomScale3D = 1.0;

  bool _isPointOverCover(Offset localPos, Size size) {
    final coverMesh = viewModel.coverMesh;
    if (coverMesh == null || !viewModel.isCoverVisible3D) return false;
    if (viewModel.isCoverLocked && !viewModel.isCover3DMoveActive) return false;
    if (size.width <= 0 || size.height <= 0) return false;

    final cx = size.width / 2.0 + viewModel.pan3D.dx;
    final cy = size.height / 2.0 + viewModel.pan3D.dy;

    final azRad = viewModel.azimuthDeg * math.pi / 180.0;
    final elRad = viewModel.elevationDeg * math.pi / 180.0;

    final cosAz = math.cos(azRad);
    final sinAz = math.sin(azRad);
    final cosEl = math.cos(elRad);
    final sinEl = math.sin(elRad);

    final mesh = viewModel.currentMesh;
    final maxDim = math.max(mesh.boundWidth, math.max(mesh.boundLength, mesh.boundHeight));
    final fitDim = maxDim > 0 ? maxDim : 200.0;
    final baseScale = (math.min(size.width, size.height) * 0.60) / fitDim;
    final scale = baseScale * viewModel.cameraZoom;

    final pivot = mesh.center;

    for (final poly in coverMesh.polygons) {
      if (poly.vertices.length < 3) continue;
      final path = Path();
      bool first = true;
      for (final p in poly.vertices) {
        final rx = p.x - pivot.x;
        final ry = p.y - pivot.y;
        final rz = p.z - pivot.z;

        final x1 = rx * cosAz - ry * sinAz;
        final y1 = rx * sinAz + ry * cosAz;
        final z1 = rz;

        final x2 = x1;
        final y2 = y1 * cosEl - z1 * sinEl;

        final sx = cx + x2 * scale;
        final sy = cy - y2 * scale;

        if (first) {
          path.moveTo(sx, sy);
          first = false;
        } else {
          path.lineTo(sx, sy);
        }
      }
      path.close();
      if (path.contains(localPos)) {
        return true;
      }
    }
    return false;
  }

  void _handleCoverDrag(Offset delta, Size size, bool isVerticalOnly) {
    final azRad = viewModel.azimuthDeg * math.pi / 180.0;
    final elRad = viewModel.elevationDeg * math.pi / 180.0;

    final cosAz = math.cos(azRad);
    final sinAz = math.sin(azRad);
    final cosEl = math.cos(elRad);
    final sinEl = math.sin(elRad);

    final mesh = viewModel.currentMesh;
    final maxDim = math.max(mesh.boundWidth, math.max(mesh.boundLength, mesh.boundHeight));
    final fitDim = maxDim > 0 ? maxDim : 200.0;
    final baseScale = (math.min(size.width, size.height) * 0.60) / fitDim;
    final scale = baseScale * viewModel.cameraZoom;

    if (scale <= 1e-6) return;

    if (isVerticalOnly) {
      final dZ = -delta.dy / scale;
      viewModel.updateCoverOffset3D(CadPoint3D(0, 0, dZ));
    } else {
      final uRightX = cosAz;
      final uRightY = -sinAz;
      final uRightZ = 0.0;

      final uUpX = sinAz * cosEl;
      final uUpY = cosAz * cosEl;
      final uUpZ = -sinEl;

      final dxCam = delta.dx / scale;
      final dyCam = -delta.dy / scale;

      final dX = uRightX * dxCam + uUpX * dyCam;
      final dY = uRightY * dxCam + uUpY * dyCam;
      final dZ = uRightZ * dxCam + uUpZ * dyCam;

      viewModel.updateCoverOffset3D(CadPoint3D(dX, dY, dZ));
    }
  }

  void _showCoverFlangeDialog(BuildContext context) {
    double currentVal = viewModel.coverFlangeDepth;
    final controller = TextEditingController(text: currentVal.toStringAsFixed(0));
    final presets = [8.0, 10.0, 12.0, 15.0, 20.0, 25.0];

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              title: Row(
                children: [
                  const Icon(Icons.straighten, size: 20, color: Color(0xFF0284C7)),
                  const SizedBox(width: 8),
                  const Text(
                    'Cover Flange Depth',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                ],
              ),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Choose or enter the downward flange height for the trunking cover.', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                    const SizedBox(height: 14),
                    const Text(
                      'Standard Presets:',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: presets.map((p) {
                        final isSel = (currentVal - p).abs() < 0.5;
                        return InkWell(
                          onTap: () {
                            setDialogState(() {
                              currentVal = p;
                              controller.text = p.toStringAsFixed(0);
                            });
                            viewModel.setCoverFlangeDepth(p);
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: isSel ? const Color(0xFF0284C7) : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: isSel ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1)),
                            ),
                            child: Text(
                              '${p.toStringAsFixed(0)} mm${p == 12.0 ? ' (Def)' : ''}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                                color: isSel ? Colors.white : const Color(0xFF334155),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text(
                          'Custom (mm):',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 80,
                          height: 32,
                          child: TextField(
                            controller: controller,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            onSubmitted: (txt) {
                              final val = double.tryParse(txt);
                              if (val != null && val >= 5.0 && val <= 100.0) {
                                setDialogState(() => currentVal = val);
                                viewModel.setCoverFlangeDepth(val);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () {
                            final val = double.tryParse(controller.text);
                            if (val != null && val >= 5.0 && val <= 100.0) {
                              setDialogState(() => currentVal = val);
                              viewModel.setCoverFlangeDepth(val);
                            }
                          },
                          child: const Text('Apply', style: TextStyle(fontSize: 11)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        return ClipRect(
          child: LayoutBuilder(
            builder: (context, constraints) {
          final size = constraints.biggest;
          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFF8FAFC), Color(0xFFE2E8F0)]),
            ),
            child: Stack(
              children: [
                // 1. Interactive Orbit, Middle-Mouse Pan & Wheel Zoom Surface
                MouseRegion(
                  cursor: _isDraggingCover
                      ? SystemMouseCursors.grabbing
                      : (!viewModel.isCoverLocked && (_isHoveringCover || viewModel.isCover3DMoveActive) ? SystemMouseCursors.grab : SystemMouseCursors.basic),
                  onHover: (event) {
                    if (_isDraggingCover) return;
                    final over = _isPointOverCover(event.localPosition, size);
                    if (_isHoveringCover != over) {
                      setState(() {
                        _isHoveringCover = over;
                      });
                    }
                  },
                  child: Listener(
                    onPointerSignal: (pointerSignal) {
                      if (widget.isInteractionLocked) return;
                      if (pointerSignal is PointerScrollEvent) {
                        final dy = pointerSignal.scrollDelta.dy;
                        final zoomFactor = dy.abs() < 40.0
                            ? math.exp(-dy * 0.003).clamp(0.85, 1.18)
                            : (dy < 0 ? 1.12 : 0.89);
                        viewModel.zoom3D(zoomFactor);
                      }
                    },
                    onPointerPanZoomStart: (event) {
                      _lastPanZoomScale3D = 1.0;
                    },
                    onPointerPanZoomUpdate: (event) {
                      if (widget.isInteractionLocked) return;
                      if (event.scale != 1.0) {
                        final incrementalScale = event.scale / _lastPanZoomScale3D;
                        _lastPanZoomScale3D = event.scale;
                        if ((incrementalScale - 1.0).abs() > 0.0001) {
                          viewModel.zoom3D(incrementalScale);
                        }
                      } else if (event.pan != Offset.zero) {
                        viewModel.pan3DCanvas(event.pan);
                      }
                    },
                    onPointerPanZoomEnd: (event) {
                      _lastPanZoomScale3D = 1.0;
                    },
                    onPointerDown: (event) {
                      if (widget.isInteractionLocked) return;
                      if ((event.buttons & kPrimaryMouseButton) != 0) {
                        if (!viewModel.isCoverLocked) {
                          final overCover = _isPointOverCover(event.localPosition, size);
                          if (overCover || viewModel.isCover3DMoveActive) {
                            _isDraggingCover = true;
                            setState(() {});
                          }
                        }
                      }
                    },
                    onPointerUp: (event) {
                      if (_isDraggingCover) {
                        _isDraggingCover = false;
                        viewModel.commitCover3DMove();
                        setState(() {});
                      }
                    },
                    onPointerCancel: (event) {
                      if (_isDraggingCover) {
                        _isDraggingCover = false;
                        setState(() {});
                      }
                    },
                    onPointerMove: (event) {
                      if (widget.isInteractionLocked) return;
                      if (_isDraggingCover) {
                        bool isShiftHeld = false;
                        try {
                          isShiftHeld = HardwareKeyboard.instance.isShiftPressed;
                        } catch (_) {}
                        _handleCoverDrag(event.delta, size, isShiftHeld || _pureVerticalDrag);
                        return;
                      }

                      final isMiddleMouse = (event.buttons & kTertiaryButton) != 0;
                      bool isShiftHeld = false;
                      try {
                        isShiftHeld = HardwareKeyboard.instance.isShiftPressed;
                      } catch (_) {}

                      if (isMiddleMouse || (isShiftHeld && (event.buttons & kPrimaryMouseButton) != 0)) {
                        // Middle mouse or Shift+Left drag -> Pan 3D camera
                        viewModel.pan3DCanvas(event.delta);
                      } else if ((event.buttons & kPrimaryMouseButton) != 0) {
                        // Left mouse drag -> Orbit turntable
                        viewModel.orbit3D(event.delta.dx * 0.5, -event.delta.dy * 0.5);
                      }
                    },
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.isInteractionLocked ? null : () => viewModel.clearSelection(),
                      child: ExcludeSemantics(
                        child: RepaintBoundary(
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
                              isOrthoProjection: viewModel.isOrthoProjection,
                              selectedBendId: viewModel.selectedBendId,
                              selectedPunchId: viewModel.selectedPunchId,
                              selectedFaceId: viewModel.selectedFaceId,
                              hoveredPunchId: viewModel.hoveredPunchId,
                              hoveredBendId: viewModel.hoveredBendId,
                              hoveredFaceId: viewModel.hoveredFaceId,
                              activePorts: viewModel.activeCmsPorts,
                              focusedPortId: viewModel.cmsGuidedController.state.focus.activePortId,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // 2. Viewport Responsive Top Controls Bar (Header Card + Presets)
                Positioned(
                  top: 12,
                  left: 12,
                  right: 88, // Clears StudioViewCube at right: 12
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left: Status & Cover Controls Card (Scrollable if constrained)
                      Flexible(
                        flex: 1,
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFCBD5E1)),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))],
                            ),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.view_in_ar, size: 14, color: Color(0xFF0284C7)),
                                  const SizedBox(width: 6),
                                  const Text(
                                    '3D FOLDED MESH',
                                    style: TextStyle(color: Color(0xFF0F172A), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                                  ),
                                  if (viewModel.hasCover) ...[
                                    const SizedBox(width: 8),
                                    Container(width: 1, height: 12, color: const Color(0xFFCBD5E1)),
                                    const SizedBox(width: 8),
                                    Tooltip(
                                      message: viewModel.isCoverVisible3D ? 'Hide Cover (3D)' : 'Show Cover (3D)',
                                      child: InkWell(
                                        onTap: viewModel.toggleCoverVisibility3D,
                                        borderRadius: BorderRadius.circular(4),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                viewModel.isCoverVisible3D ? Icons.shield : Icons.shield_outlined,
                                                size: 13,
                                                color: viewModel.isCoverVisible3D ? const Color(0xFF0284C7) : const Color(0xFF94A3B8),
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                viewModel.isCoverVisible3D ? 'Cover On' : 'Cover Off',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                  color: viewModel.isCoverVisible3D ? const Color(0xFF0284C7) : const Color(0xFF94A3B8),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (viewModel.isCoverVisible3D) ...[
                                      const SizedBox(width: 4),
                                      Tooltip(
                                        message: viewModel.coverPlacementMode3D == CoverPlacementMode3D.snappedToBase
                                            ? '3D Mode: Snapped on Base (Click to Move Beside)'
                                            : (viewModel.coverPlacementMode3D == CoverPlacementMode3D.custom
                                                  ? '3D Mode: Custom Offset (Click to Snap on Base)'
                                                  : '3D Mode: Beside Base (Click to Snap on Base)'),
                                        child: InkWell(
                                          onTap: () {
                                            final nextMode = viewModel.coverPlacementMode3D == CoverPlacementMode3D.snappedToBase
                                                ? CoverPlacementMode3D.besideBase
                                                : CoverPlacementMode3D.snappedToBase;
                                            viewModel.setCoverPlacementMode3D(nextMode);
                                          },
                                          borderRadius: BorderRadius.circular(4),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  viewModel.coverPlacementMode3D == CoverPlacementMode3D.snappedToBase
                                                      ? Icons.flip_to_front
                                                      : (viewModel.coverPlacementMode3D == CoverPlacementMode3D.custom ? Icons.open_with : Icons.flip_to_back),
                                                  size: 13,
                                                  color: const Color(0xFF8B5CF6),
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  viewModel.coverPlacementMode3D == CoverPlacementMode3D.snappedToBase
                                                      ? 'Snapped'
                                                      : (viewModel.coverPlacementMode3D == CoverPlacementMode3D.custom ? 'Moved' : 'Beside'),
                                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF8B5CF6)),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      // Lock / Unlock Cover in Position
                                      Tooltip(
                                        message: viewModel.isCoverLocked
                                            ? 'Cover Locked in Position (Click to Unlock & Move)'
                                            : 'Cover Unlocked for 3D Dragging & Move (Click to Lock)',
                                        child: InkWell(
                                          onTap: viewModel.toggleCoverLock,
                                          borderRadius: BorderRadius.circular(4),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: viewModel.isCoverLocked ? const Color(0xFFF1F5F9) : const Color(0xFFFDE68A).withValues(alpha: 0.35),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: viewModel.isCoverLocked ? const Color(0xFFCBD5E1) : const Color(0xFFD97706)),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  viewModel.isCoverLocked ? Icons.lock : Icons.lock_open,
                                                  size: 13,
                                                  color: viewModel.isCoverLocked ? const Color(0xFF64748B) : const Color(0xFFB45309),
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  viewModel.isCoverLocked ? 'Locked' : 'Unlocked',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                    color: viewModel.isCoverLocked ? const Color(0xFF64748B) : const Color(0xFFB45309),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Tooltip(
                                        message: 'Move & Explode 3D Cover (Elevation Lift & Position Controls)',
                                        child: InkWell(
                                          onTap: () {
                                            viewModel.toggleCover3DMoveActive();
                                          },
                                          borderRadius: BorderRadius.circular(4),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: viewModel.isCover3DMoveActive ? const Color(0xFF8B5CF6).withValues(alpha: 0.15) : Colors.transparent,
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: viewModel.isCover3DMoveActive ? const Color(0xFF8B5CF6) : Colors.transparent),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.open_with,
                                                  size: 13,
                                                  color: viewModel.isCover3DMoveActive ? const Color(0xFF7C3AED) : const Color(0xFF64748B),
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Move / Explode',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                    color: viewModel.isCover3DMoveActive ? const Color(0xFF7C3AED) : const Color(0xFF475569),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Tooltip(
                                        message: 'Cover Flange Depth Settings',
                                        child: InkWell(
                                          onTap: () => _showCoverFlangeDialog(context),
                                          borderRadius: BorderRadius.circular(4),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF1F5F9),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: const Color(0xFFCBD5E1)),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.straighten, size: 13, color: Color(0xFF0284C7)),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Flange ${viewModel.coverFlangeDepth.toStringAsFixed(0)}mm',
                                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF0284C7)),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Tooltip(
                                        message: 'Open Independent 3D Cover Inspector Window',
                                        child: InkWell(
                                          onTap: () {
                                            viewModel.setCover3DViewerOpen(!viewModel.isCover3DViewerOpen);
                                          },
                                          borderRadius: BorderRadius.circular(4),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                            child: Icon(
                                              Icons.open_in_new,
                                              size: 13,
                                              color: viewModel.isCover3DViewerOpen ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Right: Preset View & Display Buttons (ISO, TOP, FRONT, SIDE, GLASS, WIREFRAME, RESET)
                      Flexible(
                        flex: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))],
                          ),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _cameraButton(
                                  'ISO',
                                  () => viewModel.setPresetView(azimuth: 45, elevation: 30),
                                  isActive: (viewModel.azimuthDeg - 45).abs() < 2 && (viewModel.elevationDeg - 30).abs() < 2,
                                  tooltip: 'Isometric View (45°, 30°)',
                                ),
                                _cameraButton(
                                  'TOP',
                                  () => viewModel.setPresetView(azimuth: 0, elevation: 89),
                                  isActive: (viewModel.elevationDeg - 89).abs() < 2,
                                  tooltip: 'Top Plan View (0°, 89°)',
                                ),
                                _cameraButton(
                                  'FRONT',
                                  () => viewModel.setPresetView(azimuth: 0, elevation: 0),
                                  isActive: (viewModel.azimuthDeg).abs() < 2 && (viewModel.elevationDeg).abs() < 2,
                                  tooltip: 'Front Elevation View (0°, 0°)',
                                ),
                                _cameraButton(
                                  'RIGHT',
                                  () => viewModel.setPresetView(azimuth: 90, elevation: 0),
                                  isActive: (viewModel.azimuthDeg - 90).abs() < 2 && (viewModel.elevationDeg).abs() < 2,
                                  tooltip: 'Right Side View (90°, 0°)',
                                ),
                                _modeButton(
                                  label: 'ORTHO',
                                  isActive: viewModel.isOrthoProjection,
                                  icon: Icons.view_in_ar,
                                  tooltip: viewModel.isOrthoProjection
                                      ? 'Orthographic (Parallel) View Active — Click for Perspective'
                                      : 'Perspective View Active — Click for Orthographic',
                                  onTap: viewModel.toggleOrthoProjection,
                                ),
                                _modeButton(
                                  label: viewModel.currentEdgeChamfer > 0 ? 'CHAMFER ${viewModel.currentEdgeChamfer.toStringAsFixed(1)}mm' : 'CHAMFER',
                                  isActive: viewModel.currentEdgeChamfer > 0,
                                  icon: Icons.change_history,
                                  tooltip: 'Sheet Edge Chamfer (Bevel / Weld Prep)',
                                  onTap: () => _showChamferDialog(context),
                                ),
                                _modeButton(
                                  label: 'GLASS',
                                  isActive: viewModel.isGlassMode,
                                  icon: Icons.opacity,
                                  tooltip: 'Toggle Glass / X-Ray Mode (See Back Part)',
                                  onTap: viewModel.toggleGlassMode,
                                ),
                                if (viewModel.persistentCmsPorts.isNotEmpty)
                                  _modeButton(
                                    label: 'PORTS',
                                    isActive: viewModel.showCmsPortHighlights,
                                    icon: Icons.tag,
                                    tooltip: 'Toggle 3D Channel Port Callouts & Highlights',
                                    onTap: viewModel.toggleCmsPortHighlights,
                                  ),
                                IconButton(
                                  icon: Icon(
                                    viewModel.showWireframe ? Icons.grid_on : Icons.grid_off,
                                    size: 14,
                                    color: viewModel.showWireframe ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                                  ),
                                  tooltip: 'Toggle Wireframe',
                                  onPressed: viewModel.toggleWireframe,
                                  padding: const EdgeInsets.all(4),
                                  constraints: const BoxConstraints(),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.refresh, size: 14, color: Color(0xFF64748B)),
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
                    ],
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
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 3)],
                    ),
                    child: Text(
                      '3D Bounding: ${toNominalSize(viewModel.currentMesh.boundWidth).toStringAsFixed(0)} x ${toNominalSize(viewModel.currentMesh.boundLength).toStringAsFixed(0)} x ${toNominalSize(viewModel.currentMesh.boundHeight).toStringAsFixed(0)} mm',
                      style: const TextStyle(color: Color(0xFF0284C7), fontSize: 10, fontWeight: FontWeight.w600, fontFamily: 'monospace'),
                    ),
                  ),
                ),

                // 5. Port tags are rendered coplanar directly on the aperture face in _Viewport3dPainter PASS 3

                // 6. Secondary Floating / Draggable 3D Cover Viewer Window
                if (viewModel.isCover3DViewerOpen && viewModel.hasCover && viewModel.coverMesh != null) _FloatingCover3DViewer(viewModel: viewModel),

                // 7. Interactive 3D Cover Movement & Explode HUD
                if (viewModel.isCover3DMoveActive && viewModel.hasCover && viewModel.isCoverVisible3D)
                  _Cover3DMoveHud(viewModel: viewModel, isVerticalOnly: _pureVerticalDrag, onToggleVerticalOnly: (v) => setState(() => _pureVerticalDrag = v)),

                // 8. Real-time drag / hover status banner
                if (_isDraggingCover)
                  Positioned(
                    top: 54,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1B4B).withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 2))],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.open_with, size: 13, color: Color(0xFFA78BFA)),
                            const SizedBox(width: 6),
                            Text(
                              'Cover 3D:  X: ${viewModel.coverOffset3D.x.toStringAsFixed(0)}mm  Y: ${viewModel.coverOffset3D.y.toStringAsFixed(0)}mm  Z: ${viewModel.coverOffset3D.z >= 0 ? "+" : ""}${viewModel.coverOffset3D.z.toStringAsFixed(0)}mm',
                              style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              (HardwareKeyboard.instance.isShiftPressed || _pureVerticalDrag) ? '(Vertical Z Lift)' : '(Shift: Lock to Z)',
                              style: const TextStyle(color: Color(0xFFC4B5FD), fontSize: 9.5),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  },
);
}

  void _showChamferDialog(BuildContext context) {
    final currentChamfer = viewModel.currentEdgeChamfer;
    const presets = [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0];
    final controller = TextEditingController(text: currentChamfer > 0 ? currentChamfer.toStringAsFixed(1) : '1.0');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.change_history, color: Color(0xFF0284C7), size: 20),
            SizedBox(width: 8),
            Text('3D Sheet Edge Chamfer (Weld Prep)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
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
                    label: Text(ch == 0 ? 'None (Sharp)' : '${ch.toStringAsFixed(1)} mm'),
                    selected: isSelected,
                    selectedColor: const Color(0xFFE0F2FE),
                    labelStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF334155),
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
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Custom Chamfer Width (mm)', border: OutlineInputBorder(), isDense: true),
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
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFEF4444)),
              child: const Text('Clear All'),
            ),
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7), foregroundColor: Colors.white),
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

  Widget _cameraButton(String label, VoidCallback onTap, {bool isActive = false, String? tooltip}) {
    final btn = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF0284C7) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1),
            width: isActive ? 1.2 : 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : const Color(0xFF334155),
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
    if (tooltip != null) {
      return Tooltip(message: tooltip, child: btn);
    }
    return btn;
  }



  Widget _modeButton({required String label, required bool isActive, required IconData icon, required String tooltip, required VoidCallback onTap}) {
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
            border: Border.all(color: isActive ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1), width: isActive ? 1.2 : 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: isActive ? const Color(0xFF0284C7) : const Color(0xFF475569)),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(color: isActive ? const Color(0xFF0284C7) : const Color(0xFF334155), fontSize: 10, fontWeight: FontWeight.bold),
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
  final bool isOrthoProjection;
  final String? selectedBendId;
  final String? selectedPunchId;
  final String? selectedFaceId;
  final String? hoveredPunchId;
  final String? hoveredBendId;
  final String? hoveredFaceId;
  final List<CmsPhysicalPort> activePorts;
  final String? focusedPortId;

  _Viewport3dPainter({
    required this.mesh,
    required this.azimuthDeg,
    required this.elevationDeg,
    required this.zoom,
    required this.pan,
    required this.showWireframe,
    this.isGlassMode = false,
    this.isOrthoProjection = false,
    this.selectedBendId,
    this.selectedPunchId,
    this.selectedFaceId,
    this.hoveredPunchId,
    this.hoveredBendId,
    this.hoveredFaceId,
    this.activePorts = const [],
    this.focusedPortId,
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
    final maxDim = math.max(mesh.boundWidth, math.max(mesh.boundLength, mesh.boundHeight));
    final fitDim = maxDim > 0 ? maxDim : 200.0;
    final baseScale = (math.min(size.width, size.height) * 0.60) / fitDim;
    final scale = baseScale * zoom;

    // Center pivot point
    final pivot = mesh.center;

    // Camera perspective distance: 2.5x the model extent gives a natural 3D CAD perspective
    final cameraDist = math.max(fitDim * 2.5, 1000.0);

    // Transform a 3D point to camera space and project to screen
    ({Offset pt, double depth, CadPoint3D camPt}) project(CadPoint3D p) {
      final rx = p.x - pivot.x;
      final ry = p.y - pivot.y;
      final rz = p.z - pivot.z;

      final x1 = rx * cosAz - ry * sinAz;
      final y1 = rx * sinAz + ry * cosAz;
      final z1 = rz;

      final x2 = x1;
      final y2 = y1 * cosEl - z1 * sinEl;
      final z2 = y1 * sinEl + z1 * cosEl;

      final persp = isOrthoProjection ? 1.0 : (cameraDist / math.max(cameraDist - z2, cameraDist * 0.15));

      final sx = cx + (x2 * persp) * scale;
      final sy = cy - (y2 * persp) * scale;

      return (pt: Offset(sx, sy), depth: z2, camPt: CadPoint3D(x2, y2, z2));
    }

    // List of drawable facets sorted by camera depth
    final drawList = <_DrawFacet>[];

    for (final poly in mesh.allPolygons) {
      if (poly.vertices.length < 3) continue;

      final isFillet = poly.faceId.startsWith('FILLET_');
      final isBore = poly.faceId.startsWith('BORE_');
      final isFaceSelected = (poly.faceId == selectedFaceId);
      final isFaceHovered = (poly.faceId == hoveredFaceId);
      final isBendHighlighted =
          (selectedBendId != null && poly.faceId.contains(selectedBendId!)) || (hoveredBendId != null && poly.faceId.contains(hoveredBendId!));
      final isPunchHighlighted =
          isBore && ((selectedPunchId != null && poly.faceId.contains(selectedPunchId!)) || (hoveredPunchId != null && poly.faceId.contains(hoveredPunchId!)));
      final isHighlighted = isFaceSelected || isFaceHovered || isBendHighlighted || isPunchHighlighted;

      final n = poly.normal;

      // Camera-space outward normal vector
      final nx1 = n.x * cosAz - n.y * sinAz;
      final ny1 = n.x * sinAz + n.y * cosAz;
      final camNormalZ = ny1 * sinEl + n.z * cosEl;
      final polyCamNormal = CadPoint3D(nx1, ny1 * cosEl - n.z * sinEl, camNormalZ);

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

      // Symmetric two-sided diffuse CAD lighting:
      // Prevents sharp dark-patch discontinuities when inner and outer sheet metal walls swap depth
      final dotLight = (n.x * lightDir.x + n.y * lightDir.y + n.z * lightDir.z).abs().clamp(0.0, 1.0);
      final lightFactor = 0.65 + 0.35 * dotLight;

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
        final nx1 = n.x * cosAz - n.y * sinAz;
        final ny1 = n.x * sinAz + n.y * cosAz;
        final camNormalZ = ny1 * sinEl + n.z * cosEl;
        final polyCamNormal = CadPoint3D(nx1, ny1 * cosEl - n.z * sinEl, camNormalZ);

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

    // Step B: Topological Newell Refinement Pass
    // Resolves any pair where depth-range overlap requires order reversal in Painter's algorithm
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
        if (isGlassMode) {
          // Plate faces: render as translucent steel
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
  bool shouldRepaint(covariant _Viewport3dPainter oldDelegate) {
    return oldDelegate.mesh != mesh ||
        oldDelegate.azimuthDeg != azimuthDeg ||
        oldDelegate.elevationDeg != elevationDeg ||
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

class _FloatingCover3DViewer extends StatefulWidget {
  final SheetMetalStudioViewModel viewModel;

  const _FloatingCover3DViewer({required this.viewModel});

  @override
  State<_FloatingCover3DViewer> createState() => _FloatingCover3DViewerState();
}

class _FloatingCover3DViewerState extends State<_FloatingCover3DViewer> {
  Offset _position = const Offset(20, 70);
  double _azimuth = 45.0;
  double _elevation = 30.0;
  double _zoom = 1.0;
  Offset _pan = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final coverMesh = widget.viewModel.coverMesh;
    if (coverMesh == null) return const SizedBox.shrink();

    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: Container(
        width: 300,
        height: 250,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF0284C7), width: 1.4),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          children: [
            // Draggable Header
            GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  _position += details.delta;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: const BoxDecoration(
                  color: Color(0xFF0F172A),
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(6.6), topRight: Radius.circular(6.6)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.shield, size: 14, color: Color(0xFF38BDF8)),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'COVER 3D VIEWER',
                        style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.6),
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        setState(() {
                          _azimuth = 45.0;
                          _elevation = 30.0;
                          _zoom = 1.0;
                          _pan = Offset.zero;
                        });
                      },
                      child: const Tooltip(
                        message: 'Reset View',
                        child: Icon(Icons.refresh, size: 14, color: Color(0xFF94A3B8)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => widget.viewModel.setCover3DViewerOpen(false),
                      child: const Tooltip(
                        message: 'Close Window',
                        child: Icon(Icons.close, size: 14, color: Color(0xFF94A3B8)),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 3D Canvas
            Expanded(
              child: ClipRRect(
                child: Listener(
                  onPointerSignal: (event) {
                    if (event is PointerScrollEvent) {
                      setState(() {
                        _zoom = (_zoom * (event.scrollDelta.dy < 0 ? 1.15 : 0.87)).clamp(0.2, 5.0);
                      });
                    }
                  },
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      setState(() {
                        _azimuth = (_azimuth + details.delta.dx * 0.7) % 360.0;
                        _elevation = (_elevation - details.delta.dy * 0.7).clamp(-85.0, 85.0);
                      });
                    },
                    child: Container(
                      color: const Color(0xFFF8FAFC),
                      child: RepaintBoundary(
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _Viewport3dPainter(
                            mesh: coverMesh,
                            azimuthDeg: _azimuth,
                            elevationDeg: _elevation,
                            zoom: _zoom,
                            pan: _pan,
                            showWireframe: widget.viewModel.showWireframe,
                            isGlassMode: widget.viewModel.isGlassMode,
                            isOrthoProjection: widget.viewModel.isOrthoProjection,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: const BoxDecoration(
                color: Color(0xFFF1F5F9),
                borderRadius: BorderRadius.only(bottomLeft: Radius.circular(6.6), bottomRight: Radius.circular(6.6)),
              ),
              child: Row(
                children: [
                  Text(
                    '${toNominalSize(coverMesh.boundWidth).toStringAsFixed(0)} x ${toNominalSize(coverMesh.boundLength).toStringAsFixed(0)} x ${coverMesh.boundHeight.toStringAsFixed(0)} mm',
                    style: const TextStyle(color: Color(0xFF0284C7), fontSize: 9.5, fontWeight: FontWeight.w600, fontFamily: 'monospace'),
                  ),
                  const Spacer(),
                  const Text('Drag to orbit • Scroll to zoom', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 9)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cover3DMoveHud extends StatefulWidget {
  final SheetMetalStudioViewModel viewModel;
  final bool isVerticalOnly;
  final ValueChanged<bool> onToggleVerticalOnly;

  const _Cover3DMoveHud({required this.viewModel, required this.isVerticalOnly, required this.onToggleVerticalOnly});

  @override
  State<_Cover3DMoveHud> createState() => _Cover3DMoveHudState();
}

class _Cover3DMoveHudState extends State<_Cover3DMoveHud> {
  Offset _position = const Offset(12, 60);

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final cover = vm.document.cover;
    if (cover == null) return const SizedBox.shrink();

    final offset = cover.offset3D;
    final liftZ = offset.z;

    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: Container(
        width: 300,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF8B5CF6), width: 1.4),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Draggable Header
            GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  _position += details.delta;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: const BoxDecoration(
                  color: Color(0xFF1E1B4B),
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(6.6), topRight: Radius.circular(6.6)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.open_with, size: 14, color: Color(0xFFA78BFA)),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        '3D COVER POSITION & EXPLODE',
                        style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold, letterSpacing: 0.4),
                      ),
                    ),
                    InkWell(
                      onTap: () => vm.setCover3DMoveActive(false),
                      borderRadius: BorderRadius.circular(4),
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(Icons.close, size: 14, color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Vertical Z Lift / Explode Slider
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Vertical Lift (Z-Axis):',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3E8FF),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFFC084FC)),
                        ),
                        child: Text(
                          liftZ >= 0 ? '+${liftZ.toStringAsFixed(0)} mm' : '${liftZ.toStringAsFixed(0)} mm',
                          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF7E22CE), fontFamily: 'monospace'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      activeTrackColor: const Color(0xFF8B5CF6),
                      inactiveTrackColor: const Color(0xFFE2E8F0),
                      thumbColor: const Color(0xFF7C3AED),
                      overlayColor: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                    ),
                    child: Slider(
                      min: 0.0,
                      max: math.max(250.0, liftZ + 50.0),
                      value: liftZ.clamp(0.0, math.max(250.0, liftZ + 50.0)),
                      onChanged: (val) {
                        vm.setCoverLiftZ(val);
                      },
                      onChangeEnd: (_) {
                        vm.commitCover3DMove();
                      },
                    ),
                  ),

                  // Quick Lift presets
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      _presetChip('Snap (0)', liftZ == 0, () {
                        vm.setCoverLiftZ(0);
                        vm.commitCover3DMove();
                      }),
                      _presetChip('+30mm', (liftZ - 30).abs() < 1, () {
                        vm.setCoverLiftZ(30);
                        vm.commitCover3DMove();
                      }),
                      _presetChip('+60mm', (liftZ - 60).abs() < 1, () {
                        vm.setCoverLiftZ(60);
                        vm.commitCover3DMove();
                      }),
                      _presetChip('+100mm', (liftZ - 100).abs() < 1, () {
                        vm.setCoverLiftZ(100);
                        vm.commitCover3DMove();
                      }),
                      _presetChip('+150mm', (liftZ - 150).abs() < 1, () {
                        vm.setCoverLiftZ(150);
                        vm.commitCover3DMove();
                      }),
                    ],
                  ),

                  const SizedBox(height: 10),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  const SizedBox(height: 8),

                  // Cover Flange Depth Controls
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Flange Depth:',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                      ),
                      Text(
                        '${vm.coverFlangeDepth.toStringAsFixed(0)} mm',
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF0284C7), fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      _presetChip('8mm', (vm.coverFlangeDepth - 8).abs() < 0.5, () => vm.setCoverFlangeDepth(8)),
                      _presetChip('10mm', (vm.coverFlangeDepth - 10).abs() < 0.5, () => vm.setCoverFlangeDepth(10)),
                      _presetChip('12mm (Def)', (vm.coverFlangeDepth - 12).abs() < 0.5, () => vm.setCoverFlangeDepth(12)),
                      _presetChip('15mm', (vm.coverFlangeDepth - 15).abs() < 0.5, () => vm.setCoverFlangeDepth(15)),
                      _presetChip('20mm', (vm.coverFlangeDepth - 20).abs() < 0.5, () => vm.setCoverFlangeDepth(20)),
                    ],
                  ),

                  const SizedBox(height: 10),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  const SizedBox(height: 8),

                  // 2. 3D Coordinates (X, Y, Z offsets)
                  const Text(
                    'Position Offset (mm):',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: _axisStepper(
                          label: 'X',
                          val: offset.x,
                          onDec: () {
                            vm.updateCoverOffset3D(const CadPoint3D(-10, 0, 0));
                            vm.commitCover3DMove();
                          },
                          onInc: () {
                            vm.updateCoverOffset3D(const CadPoint3D(10, 0, 0));
                            vm.commitCover3DMove();
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _axisStepper(
                          label: 'Y',
                          val: offset.y,
                          onDec: () {
                            vm.updateCoverOffset3D(const CadPoint3D(0, -10, 0));
                            vm.commitCover3DMove();
                          },
                          onInc: () {
                            vm.updateCoverOffset3D(const CadPoint3D(0, 10, 0));
                            vm.commitCover3DMove();
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _axisStepper(
                          label: 'Z',
                          val: offset.z,
                          onDec: () {
                            vm.updateCoverOffset3D(const CadPoint3D(0, 0, -10));
                            vm.commitCover3DMove();
                          },
                          onInc: () {
                            vm.updateCoverOffset3D(const CadPoint3D(0, 0, 10));
                            vm.commitCover3DMove();
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  const SizedBox(height: 8),

                  // 3. Quick Actions (Snap to Rim, Beside Base, Reset)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.flip_to_front, size: 12),
                          label: const Text('Snap to Rim', style: TextStyle(fontSize: 9.5)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF4338CA),
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                            side: const BorderSide(color: Color(0xFFC7D2FE)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          ),
                          onPressed: () {
                            vm.setCoverPlacementMode3D(CoverPlacementMode3D.snappedToBase);
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.flip_to_back, size: 12),
                          label: const Text('Beside Base', style: TextStyle(fontSize: 9.5)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF0F766E),
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                            side: const BorderSide(color: Color(0xFF99F6E4)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          ),
                          onPressed: () {
                            vm.setCoverPlacementMode3D(CoverPlacementMode3D.besideBase);
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        icon: const Icon(Icons.replay, size: 14),
                        tooltip: 'Reset 3D Offset to (0,0,0)',
                        style: IconButton.styleFrom(padding: const EdgeInsets.all(6), backgroundColor: const Color(0xFFF1F5F9)),
                        onPressed: () {
                          vm.resetCover3DOffset();
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),
                  // Drag mode toggle (Lock to Z-lift vs Free 3D)
                  InkWell(
                    onTap: () {
                      widget.onToggleVerticalOnly(!widget.isVerticalOnly);
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        color: widget.isVerticalOnly ? const Color(0xFFF3E8FF) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: widget.isVerticalOnly ? const Color(0xFFC084FC) : const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            widget.isVerticalOnly ? Icons.check_box : Icons.check_box_outline_blank,
                            size: 13,
                            color: widget.isVerticalOnly ? const Color(0xFF7C3AED) : const Color(0xFF94A3B8),
                          ),
                          const SizedBox(width: 5),
                          const Expanded(
                            child: Text(
                              'Lock Drag to Vertical Z (or hold Shift)',
                              style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w500, color: Color(0xFF475569)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.touch_app, size: 12, color: Color(0xFF64748B)),
                        SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Click & drag cover in viewport. Hold Shift for pure vertical Z-lift.',
                            style: TextStyle(fontSize: 9, color: Color(0xFF64748B)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _presetChip(String label, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF7C3AED) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: isSelected ? const Color(0xFF6D28D9) : const Color(0xFFCBD5E1)),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 9, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500, color: isSelected ? Colors.white : const Color(0xFF475569)),
        ),
      ),
    );
  }

  Widget _axisStepper({required String label, required double val, required VoidCallback onDec, required VoidCallback onInc}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
              ),
              Text(
                val.toStringAsFixed(0),
                style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A), fontFamily: 'monospace'),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onDec,
                  borderRadius: BorderRadius.circular(2),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    color: const Color(0xFFE2E8F0),
                    alignment: Alignment.center,
                    child: const Text('-', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: InkWell(
                  onTap: onInc,
                  borderRadius: BorderRadius.circular(2),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    color: const Color(0xFFE2E8F0),
                    alignment: Alignment.center,
                    child: const Text('+', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
