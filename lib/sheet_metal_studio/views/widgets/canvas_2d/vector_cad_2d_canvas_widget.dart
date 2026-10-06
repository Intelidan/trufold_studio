import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:trufold_studio/sheet_metal_studio/models/fold_bend_line.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';
import '../unfolded_canvas_widget.dart';

/// Modern 2D Vector CAD Canvas Studio Widget.
/// Operates directly on the active [SheetMetalStudioViewModel] and [DsfDocument],
/// providing the full suite of CAD functionality:
/// - Unfolded sheet metal blank geometry (faces, contours, cut slits)
/// - Interactive bend lines with angle tags, direction (UP/DN), bend radius, and auto-edge candidate preview
/// - Flange lines with live edge snap and parametric settings
/// - Punch tooling (round holes, obround slots, square/rectangular cutouts, perforation patterns)
/// - Geometric constraints (badges, hover highlights, FloatingSketchConstraintBar)
/// - Full dimensions (linear, angular, radial) with witness lines and inline in-place driving editor
/// - Entity property inspector panel ([CadPropertyInspector])
/// - Live coordinate crosshair HUD (X, Y, Snap Active)
/// - Live Diagnostics & Metrics row (Elements count, Active tool, Inspected scope, Bounds)
/// - DXF / DSF file ingestion and direct 3D model synchronization
class VectorCad2DCanvasWidget extends StatefulWidget {
  final SheetMetalStudioViewModel viewModel;
  final VoidCallback? onSwitchToLegacyCanvas;

  const VectorCad2DCanvasWidget({
    super.key,
    required this.viewModel,
    this.onSwitchToLegacyCanvas,
  });

  @override
  State<VectorCad2DCanvasWidget> createState() => _VectorCad2DCanvasWidgetState();
}

class _VectorCad2DCanvasWidgetState extends State<VectorCad2DCanvasWidget> {
  bool _liveSyncTo3d = true;

  @override
  void initState() {
    super.initState();
    widget.viewModel.addListener(_onViewModelChanged);
  }

  @override
  void didUpdateWidget(covariant VectorCad2DCanvasWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel != widget.viewModel) {
      oldWidget.viewModel.removeListener(_onViewModelChanged);
      widget.viewModel.addListener(_onViewModelChanged);
    }
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_onViewModelChanged);
    super.dispose();
  }

  void _onViewModelChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _handleImportFile() async {
    try {
      final List<PlatformFile> files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['dxf', 'dsf'],
      );

      if (files.isNotEmpty) {
        final file = files.first;
        final bytes = await file.readAsBytes();
        final content = utf8.decode(bytes);

        if (content.isNotEmpty) {
          final ext = (file.extension ?? '').toLowerCase();
          if (ext == 'dsf' || content.trim().startsWith('{')) {
            widget.viewModel.loadDsf(content);
          } else {
            widget.viewModel.loadDxf(content, productType: file.name);
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Successfully imported ${file.name} into 2D CAD & 3D model!'),
                backgroundColor: const Color(0xFF10B981),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import error: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  void _syncTo3d() {
    widget.viewModel.setFoldProgress(widget.viewModel.foldProgress);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('2D CAD sketch synchronized to 3D ThreeJS model!'),
          backgroundColor: Color(0xFF0284C7),
          duration: Duration(milliseconds: 1500),
        ),
      );
    }
  }

  String _getInspectedScopeLabel(SheetMetalStudioViewModel vm) {
    final doc = vm.document;
    if (vm.selectedBendId != null) {
      final bend = doc.bends.where((b) => b.id == vm.selectedBendId).firstOrNull;
      if (bend != null) {
        final dirStr = bend.direction == BendDirection.up ? 'UP' : 'DN';
        return 'Bend #${bend.id} (${bend.displayAngleDeg.toStringAsFixed(0)}° $dirStr, R:${bend.radiusMm}mm)';
      }
      return 'Bend #${vm.selectedBendId}';
    }
    if (vm.selectedPunchId != null) {
      final punch = doc.punches.where((p) => p.id == vm.selectedPunchId).firstOrNull;
      if (punch != null) {
        return 'Punch #${punch.id} (${punch.type.name}, Ø:${punch.diameterMm.toStringAsFixed(1)}mm)';
      }
      return 'Punch #${vm.selectedPunchId}';
    }
    if (vm.selectedCutId != null) {
      final cut = doc.cutLines.where((c) => c.id == vm.selectedCutId).firstOrNull;
      if (cut != null) {
        return 'Cut Slit #${cut.id} (${cut.length.toStringAsFixed(1)}mm)';
      }
      return 'Cut Line #${vm.selectedCutId}';
    }
    if (vm.selectedFaceId != null) {
      final face = doc.faces.where((f) => f.id == vm.selectedFaceId).firstOrNull;
      if (face != null) {
        return 'Face #${face.id} (${face.vertices.length} vertices)';
      }
      return 'Face #${vm.selectedFaceId}';
    }
    if (vm.selectedDimensionId != null) {
      final dim = doc.dimensions.where((d) => d.id == vm.selectedDimensionId).firstOrNull;
      if (dim != null) {
        return 'Dimension #${dim.id} (${dim.measuredValue.toStringAsFixed(1)}mm)';
      }
      return 'Dimension #${vm.selectedDimensionId}';
    }
    if (vm.selectedConstraintId != null) {
      final con = vm.activeConstraintDefinitions.where((c) => c.id == vm.selectedConstraintId).firstOrNull;
      if (con != null) {
        return 'Constraint #${con.id} (${con.type.name})';
      }
      return 'Constraint #${vm.selectedConstraintId}';
    }
    if (vm.selectedEntityIds.isNotEmpty) {
      return '${vm.selectedEntityIds.length} entities selected';
    }
    return 'None (Blank Sheet Canvas)';
  }

  String _formatToolName(StudioToolMode mode) {
    switch (mode) {
      case StudioToolMode.select:
        return 'Select Entity';
      case StudioToolMode.pan:
        return 'Pan Canvas';
      case StudioToolMode.addBend:
        return 'Add Bend Line';
      case StudioToolMode.addFlange:
        return 'Add Return Flange';
      case StudioToolMode.addCut:
        return 'Add Laser Cut';
      case StudioToolMode.addPunchRound:
        return 'Stamp Round Punch';
      case StudioToolMode.addPunchObround:
        return 'Stamp Obround Slot';
      case StudioToolMode.addPunchSquare:
        return 'Stamp Rect Punch';
      case StudioToolMode.drawRectangle:
        return 'Draw Rectangle';
      case StudioToolMode.drawCircle:
        return 'Draw Circle';
      case StudioToolMode.drawArc:
        return 'Draw 3-Pt Arc';
      case StudioToolMode.drawPolyline:
        return 'Draw Polyline';
      case StudioToolMode.cornerFillet:
        return 'Corner Fillet';
      case StudioToolMode.cornerChamfer:
        return 'Corner Chamfer';
      case StudioToolMode.setBaseAnchor:
        return 'Set Base Anchor';
      case StudioToolMode.addDimension:
        return 'Add Dimension';
      case StudioToolMode.dragDimension:
        return 'Drag Dimension';
      default:
        return mode.name;
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final doc = vm.document;

    final int totalElements = doc.faces.length +
        doc.bends.length +
        doc.punches.length +
        doc.cutLines.length +
        doc.dimensions.length +
        vm.activeConstraintDefinitions.length;

    return Container(
      color: const Color(0xFF0A0F1D),
      child: Column(
        children: [
          // 1. TOP DRAFTING & 3D SYNC ACTION BAR
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              border: Border(bottom: BorderSide(color: Color(0xFF1E293B), width: 1.2)),
            ),
            child: Row(
              children: [
                // Title Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.6)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.architecture, size: 14, color: Color(0xFF38BDF8)),
                      SizedBox(width: 5),
                      Text(
                        '2D CAD STUDIO',
                        style: TextStyle(
                          color: Color(0xFF38BDF8),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Open DXF / DSF Button
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E293B),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    elevation: 0,
                    side: const BorderSide(color: Color(0xFF334155)),
                  ),
                  icon: const Icon(Icons.folder_open, size: 14, color: Color(0xFF38BDF8)),
                  label: const Text('Open DXF / DSF', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  onPressed: _handleImportFile,
                ),

                const SizedBox(width: 6),

                // Sync to 3D Model Button
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.view_in_ar, size: 14, color: Colors.white),
                  label: const Text('Sync to 3D Model', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  onPressed: _syncTo3d,
                ),

                const SizedBox(width: 6),

                // Live 3D Toggle
                InkWell(
                  onTap: () => setState(() => _liveSyncTo3d = !_liveSyncTo3d),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _liveSyncTo3d ? const Color(0xFF064E3B) : const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _liveSyncTo3d ? const Color(0xFF10B981) : const Color(0xFF334155),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.bolt,
                          size: 13,
                          color: _liveSyncTo3d ? const Color(0xFF34D399) : const Color(0xFF94A3B8),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Live 3D: ${_liveSyncTo3d ? "ON" : "OFF"}',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: _liveSyncTo3d ? const Color(0xFF34D399) : const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const Spacer(),

                // Undo
                IconButton(
                  icon: const Icon(Icons.undo, size: 16),
                  color: vm.canUndo ? const Color(0xFF38BDF8) : const Color(0xFF475569),
                  tooltip: 'Undo (Ctrl+Z)',
                  onPressed: vm.canUndo ? vm.undo : null,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),

                // Redo
                IconButton(
                  icon: const Icon(Icons.redo, size: 16),
                  color: vm.canRedo ? const Color(0xFF38BDF8) : const Color(0xFF475569),
                  tooltip: 'Redo (Ctrl+Y)',
                  onPressed: vm.canRedo ? vm.redo : null,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),

                const SizedBox(width: 4),

                // Zoom to Fit
                IconButton(
                  icon: const Icon(Icons.fit_screen, size: 16),
                  color: const Color(0xFFF1F5F9),
                  tooltip: 'Reset / Fit View',
                  onPressed: vm.reset2DCanvas,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),

                const SizedBox(width: 4),

                // Grid Snap Toggle Button
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: vm.snapSettings.enableGrid ? const Color(0xFF2563EB) : const Color(0xFF334155),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  onPressed: vm.toggleGridSnap,
                  child: Text(
                    vm.snapSettings.enableGrid ? 'Grid Snap: ON' : 'Grid Snap: OFF',
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                  ),
                ),

                const SizedBox(width: 6),

                // Toggle CAD Property Inspector
                IconButton(
                  icon: Icon(
                    Icons.tune,
                    size: 16,
                    color: vm.isPropertyInspectorOpen ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8),
                  ),
                  tooltip: 'Toggle CAD Property Inspector (Ctrl+I / F4)',
                  onPressed: vm.togglePropertyInspector,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),

                if (widget.onSwitchToLegacyCanvas != null) ...[
                  const SizedBox(width: 6),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF94A3B8),
                      side: const BorderSide(color: Color(0xFF334155)),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    icon: const Icon(Icons.swap_horiz, size: 13),
                    label: const Text('Legacy View', style: TextStyle(fontSize: 10.5)),
                    onPressed: widget.onSwitchToLegacyCanvas,
                  ),
                ],
              ],
            ),
          ),

          // 2. CENTRAL FULL 2D VECTOR CAD VIEWPORT
          Expanded(
            child: ClipRect(
              child: UnfoldedCanvasWidget(
                key: const ValueKey('vector_cad_dark_unfolded_canvas'),
                viewModel: widget.viewModel,
                isDarkTheme: true,
                renderFloatingInspectors: true,
                showInCanvasToolRibbon: true,
                showLiveCoordinateHud: true,
              ),
            ),
          ),

          // 3. DIAGNOSTICS & METRICS ROW (Elements, Tool, Scope, Bounds)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              border: Border(top: BorderSide(color: Color(0xFF1E293B), width: 1.2)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMetricCol('Elements count', '$totalElements units', const Color(0xFF38BDF8)),
                _buildMetricCol('Active terminal tool', _formatToolName(vm.toolMode), const Color(0xFFF1F5F9)),
                _buildMetricCol('Inspected scope', _getInspectedScopeLabel(vm), const Color(0xFFF59E0B)),
                _buildMetricCol(
                  'Perimeter bounds',
                  '${doc.blankWidthMm.toStringAsFixed(1)} × ${doc.blankLengthMm.toStringAsFixed(1)} mm',
                  const Color(0xFF10B981),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCol(String label, String value, Color valueColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.bold,
            color: valueColor,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}
