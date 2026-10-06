import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trufold_studio/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart';
import 'controllers/vector_cad_controller.dart';
import 'engine/cad_vector_painter.dart';
import 'models/vector_cad_entity.dart';

/// Modern 2D Vector CAD Canvas Drafting Widget.
/// Implements ultra-responsive 120 FPS direct vector drafting with grid snapping,
/// live crosshair diagnostics, selection inspection, and DSF/3D model synchronization.
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
  late final VectorCadController _controller;
  bool _isDragging = false;
  bool _isMovingEntity = false;
  Offset _moveStartMm = Offset.zero;
  Offset _dragStartMm = Offset.zero;
  Offset _currentCursorMm = const Offset(680.0, 440.0);
  bool _isPanning = false;
  Offset _panStartScreen = Offset.zero;
  Offset _panBaseOffset = Offset.zero;

  @override
  void initState() {
    super.initState();
    _controller = VectorCadController();
    _controller.addListener(_onControllerUpdate);

    // Initial load from active CAD fitting if geometry is present
    if (widget.viewModel.document.faces.isNotEmpty || widget.viewModel.document.bends.isNotEmpty) {
      _controller.loadFromDsfDocument(widget.viewModel.document);
    }
  }

  @override
  void didUpdateWidget(covariant VectorCad2DCanvasWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel.document != widget.viewModel.document) {
      if (widget.viewModel.document.faces.isNotEmpty || widget.viewModel.document.bends.isNotEmpty) {
        _controller.loadFromDsfDocument(widget.viewModel.document);
      }
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdate);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  // Convert Screen pixel coordinates to CAD millimeters
  Offset _screenToMm(Offset screenPt) {
    return (screenPt - _controller.panOffset) / _controller.scale;
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
            _controller.loadDsfString(content);
            widget.viewModel.loadDsf(content);
          } else {
            _controller.loadDxfString(content, productType: file.name);
            widget.viewModel.loadDxf(content, productType: file.name);
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Successfully imported ${file.name} to 2D Canvas & 3D Viewport!'),
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
    _controller.syncToViewModel(widget.viewModel);
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

  void _handlePointerDown(PointerDownEvent e) {
    if (e.buttons == kMiddleMouseButton ||
        (e.buttons == kPrimaryMouseButton && HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.space))) {
      _isPanning = true;
      _panStartScreen = e.localPosition;
      _panBaseOffset = _controller.panOffset;
      return;
    }

    if (e.buttons != kPrimaryMouseButton) return;

    final rawMm = _screenToMm(e.localPosition);
    final snap = _controller.computeSnap(rawMm);
    final startPt = snap.point;

    _isDragging = true;
    _dragStartMm = startPt;
    _currentCursorMm = startPt;

    final tool = _controller.activeTool;
    if (tool == VectorCadTool.select) {
      final selected = _controller.selectedEntity;
      if (selected != null && selected.hitTest(startPt, 8.0 / _controller.scale)) {
        _isMovingEntity = true;
        _moveStartMm = startPt;
      } else {
        _controller.selectAt(startPt);
        if (_controller.selectedEntity != null) {
          _isMovingEntity = true;
          _moveStartMm = startPt;
        }
      }
    } else if (tool == VectorCadTool.line) {
      _controller.updateTempEntity(
        VectorCadLine(
          id: 'temp_line',
          label: 'Construction Line',
          p1: startPt,
          p2: startPt,
          color: const Color(0xFFFFCC00),
        ),
      );
    } else if (tool == VectorCadTool.rect) {
      _controller.updateTempEntity(
        VectorCadRect(
          id: 'temp_rect',
          label: 'Construction Rectangle',
          p1: startPt,
          p2: startPt,
          color: const Color(0xFFFFCC00),
        ),
      );
    } else if (tool == VectorCadTool.circle) {
      _controller.updateTempEntity(
        VectorCadCircle(
          id: 'temp_circle',
          label: 'Construction Circle',
          center: startPt,
          radius: 0.0,
          color: const Color(0xFFFFCC00),
        ),
      );
    }
  }

  void _handlePointerMove(PointerMoveEvent e) {
    if (_isPanning) {
      final delta = e.localPosition - _panStartScreen;
      _controller.setPanAndScale(_panBaseOffset + delta, _controller.scale);
      return;
    }

    final rawMm = _screenToMm(e.localPosition);
    final snap = _controller.computeSnap(rawMm);
    final curPt = snap.point;

    setState(() {
      _currentCursorMm = curPt;
    });

    if (!_isDragging) return;

    if (_isMovingEntity) {
      final delta = curPt - _moveStartMm;
      if (delta.distanceSquared > 0.001) {
        _controller.moveSelected(delta);
        _moveStartMm = curPt;
      }
      return;
    }

    final tool = _controller.activeTool;
    if (tool == VectorCadTool.line) {
      _controller.updateTempEntity(
        VectorCadLine(
          id: 'temp_line',
          label: 'Line ${_controller.entities.length + 1}',
          p1: _dragStartMm,
          p2: curPt,
          color: const Color(0xFFFFCC00),
        ),
      );
    } else if (tool == VectorCadTool.rect) {
      _controller.updateTempEntity(
        VectorCadRect(
          id: 'temp_rect',
          label: 'Rectangle ${_controller.entities.length + 1}',
          p1: _dragStartMm,
          p2: curPt,
          color: const Color(0xFFFFCC00),
        ),
      );
    } else if (tool == VectorCadTool.circle) {
      final r = (curPt - _dragStartMm).distance;
      _controller.updateTempEntity(
        VectorCadCircle(
          id: 'temp_circle',
          label: 'Circle ${_controller.entities.length + 1}',
          center: _dragStartMm,
          radius: r,
          color: const Color(0xFFFFCC00),
        ),
      );
    }
  }

  void _handlePointerUp(PointerUpEvent e) {
    if (_isPanning) {
      _isPanning = false;
      return;
    }

    if (!_isDragging) return;
    _isDragging = false;

    if (_isMovingEntity) {
      _isMovingEntity = false;
      _controller.commitMove();
      if (_controller.liveSyncTo3d) {
        _controller.syncToViewModel(widget.viewModel);
      }
      return;
    }

    final temp = _controller.tempEntity;
    if (temp != null) {
      bool isValid = false;
      if (temp is VectorCadLine && temp.length > 2.0) isValid = true;
      if (temp is VectorCadRect && temp.width > 2.0 && temp.height > 2.0) isValid = true;
      if (temp is VectorCadCircle && temp.radius > 2.0) isValid = true;

      if (isValid) {
        final newEntity = temp.copyWith(
          isSelected: true,
          color: const Color(0xFF00FFCC),
        );
        _controller.addEntity(newEntity);
        if (_controller.liveSyncTo3d) {
          _controller.syncToViewModel(widget.viewModel);
        }
      }
      _controller.updateTempEntity(null);
    }
  }

  void _handlePointerSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      final zoomFactor = e.scrollDelta.dy < 0 ? 1.12 : 0.88;
      final mouseScreen = e.localPosition;
      final mouseMm = _screenToMm(mouseScreen);

      final newScale = (_controller.scale * zoomFactor).clamp(0.15, 10.0);
      final newPan = mouseScreen - mouseMm * newScale;

      _controller.setPanAndScale(newPan, newScale);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF1F5F9), // Slate 100 workbench backdrop
      child: Column(
        children: [
          // 1. PRIMARY VIEWPORT CONTAINER (Dark CAD Grid matching screenshot)
          Expanded(
            flex: 3,
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D0D),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF334155), width: 1.5),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: Stack(
                  children: [
                    // Interactive Canvas Surface
                    Positioned.fill(
                      child: Listener(
                        onPointerDown: _handlePointerDown,
                        onPointerMove: _handlePointerMove,
                        onPointerUp: _handlePointerUp,
                        onPointerSignal: _handlePointerSignal,
                        child: CustomPaint(
                          painter: CadVectorPainter(
                            entities: _controller.entities,
                            selectedEntity: _controller.selectedEntity,
                            tempEntity: _controller.tempEntity,
                            snapResult: _controller.lastSnapResult,
                            panOffset: _controller.panOffset,
                            scale: _controller.scale,
                            gridSizeMm: _controller.gridSizeMm,
                            showGrid: true,
                          ),
                        ),
                      ),
                    ),

                    // Top-Right Scale Pill Badge (Exact match to screenshot)
                    Positioned(
                      top: 14,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                        decoration: BoxDecoration(
                          color: const Color(0xCC1E293B),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF475569), width: 1.0),
                        ),
                        child: Text(
                          'Scale: ${(_controller.scale).toStringAsFixed(0)}px = 1mm',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                        ),
                      ),
                    ),

                    // Top-Left Legacy Toggle Switch
                    if (widget.onSwitchToLegacyCanvas != null)
                      Positioned(
                        top: 14,
                        left: 16,
                        child: InkWell(
                          onTap: widget.onSwitchToLegacyCanvas,
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                            decoration: BoxDecoration(
                              color: const Color(0xDD0F172A),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF0284C7), width: 1.1),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.sync_alt, size: 12, color: Color(0xFF38BDF8)),
                                SizedBox(width: 6),
                                Text(
                                  'Switch to Legacy Canvas',
                                  style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    // Bottom-Left Live Crosshair & Snap Badge (Exact match to screenshot)
                    Positioned(
                      bottom: 14,
                      left: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xDD000000),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF334155), width: 1.0),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('X: ', style: TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.bold)),
                            Text(
                              _currentCursorMm.dx.round().toString(),
                              style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                            ),
                            const SizedBox(width: 12),
                            const Text('Y: ', style: TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.bold)),
                            Text(
                              _currentCursorMm.dy.round().toString(),
                              style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                            ),
                            if (_controller.isGridSnapEnabled) ...[
                              const SizedBox(width: 14),
                              Container(
                                width: 7,
                                height: 7,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFF59E0B),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'Snap Active',
                                style: TextStyle(color: Color(0xFFF59E0B), fontSize: 11.5, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 2. DIAGNOSTICS & METRICS ROW (Matching user screenshot)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2)),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMetricCol('Elements count', '${_controller.elementsCount} units', const Color(0xFF0F172A)),
                _buildMetricCol('Active terminal tool', _toolName(_controller.activeTool), const Color(0xFF0F172A)),
                _buildMetricCol('Inspected scope', _controller.selectedScopeLabel, const Color(0xFF2563EB)),
                _buildMetricCol(
                  'Perimeter bounds',
                  _controller.selectedEntity != null ? '${_controller.selectedPerimeter.toStringAsFixed(1)}mm' : '---',
                  const Color(0xFF10B981),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // 3. CONTROLS, DRAFTING MODES, AND PRESETS (Matching user screenshot)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Action Buttons Row: File Import, Sync to 3D, Zoom, Undo, Redo, Grid Snap
                Row(
                  children: [
                    // Import DXF / DSF Button
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F172A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.folder_open, size: 15, color: Color(0xFF38BDF8)),
                      label: const Text('Open DXF / DSF', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      onPressed: _handleImportFile,
                    ),

                    const SizedBox(width: 8),

                    // Sync to 3D Model Button
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0284C7),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.view_in_ar, size: 15, color: Colors.white),
                      label: const Text('Sync to 3D Model', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      onPressed: _syncTo3d,
                    ),

                    const SizedBox(width: 8),

                    // Live 3D Sync Toggle Switch
                    InkWell(
                      onTap: () => _controller.setLiveSyncTo3d(!_controller.liveSyncTo3d),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _controller.liveSyncTo3d ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _controller.liveSyncTo3d ? const Color(0xFF86EFAC) : const Color(0xFFCBD5E1)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bolt, size: 14, color: _controller.liveSyncTo3d ? const Color(0xFF16A34A) : const Color(0xFF64748B)),
                            const SizedBox(width: 4),
                            Text(
                              'Live 3D: ${_controller.liveSyncTo3d ? "ON" : "OFF"}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _controller.liveSyncTo3d ? const Color(0xFF15803D) : const Color(0xFF475569),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const Spacer(),

                    // Undo Button
                    IconButton(
                      icon: const Icon(Icons.undo, size: 18),
                      color: _controller.canUndo ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1),
                      tooltip: 'Undo',
                      onPressed: _controller.canUndo ? _controller.undo : null,
                    ),

                    // Redo Button
                    IconButton(
                      icon: const Icon(Icons.redo, size: 18),
                      color: _controller.canRedo ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1),
                      tooltip: 'Redo',
                      onPressed: _controller.canRedo ? _controller.redo : null,
                    ),

                    const SizedBox(width: 4),

                    // Zoom to Fit
                    IconButton(
                      icon: const Icon(Icons.fit_screen, size: 18),
                      color: const Color(0xFF0F172A),
                      tooltip: 'Zoom to Fit',
                      onPressed: () {
                        final renderBox = context.findRenderObject() as RenderBox?;
                        if (renderBox != null) {
                          _controller.zoomToFit(renderBox.size);
                        }
                      },
                    ),

                    const SizedBox(width: 8),

                    // Grid Snap Toggle Button
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _controller.isGridSnapEnabled ? const Color(0xFF2563EB) : const Color(0xFF64748B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      onPressed: _controller.toggleGridSnap,
                      child: Text(
                        _controller.isGridSnapEnabled ? 'Disable Grid Snap' : 'Enable Grid Snap',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Tool Mode Buttons & Presets Row
                Row(
                  children: [
                    const Text(
                      'Drafting Tool Mode',
                      style: TextStyle(color: Color(0xFF334155), fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 14),

                    // Drafting Tool Group: Line, Box, Circle, Select
                    _buildToolPill(VectorCadTool.line, 'Line Dr...'),
                    const SizedBox(width: 6),
                    _buildToolPill(VectorCadTool.rect, 'Box O...'),
                    const SizedBox(width: 6),
                    _buildToolPill(VectorCadTool.circle, 'Circle'),
                    const SizedBox(width: 6),
                    _buildToolPill(VectorCadTool.select, 'Select ...'),

                    const Spacer(),

                    // Presets Dropdown
                    Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: 'reducer',
                          style: const TextStyle(color: Color(0xFF1E293B), fontSize: 11, fontWeight: FontWeight.w600),
                          items: const [
                            DropdownMenuItem(value: 'reducer', child: Text('Straight Reducer 150×100')),
                            DropdownMenuItem(value: 'chassis', child: Text('Formed Electronics Chassis')),
                            DropdownMenuItem(value: 'active_3d', child: Text('Sync from 3D Model')),
                          ],
                          onChanged: (val) {
                            if (val == 'active_3d') {
                              _controller.loadFromDsfDocument(widget.viewModel.document);
                            } else if (val != null) {
                              _controller.loadBlueprintPreset(val);
                            }
                          },
                        ),
                      ),
                    ),

                    const SizedBox(width: 10),

                    // Clear Element Button (Red button matching screenshot)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.delete, size: 14),
                      label: const Text('Clear Element', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      onPressed: _controller.deleteSelected,
                    ),
                  ],
                ),

                // Selected Entity Inspector Strip
                if (_controller.selectedEntity != null) ...[
                  const SizedBox(height: 10),
                  _buildSelectedEntityInspector(),
                ],

                const SizedBox(height: 12),

                // Bottom Info Tip Banner (Exact match to screenshot)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F9FF),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFBAE6FD)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info, size: 16, color: Color(0xFF0284C7)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _getTipText(_controller.activeTool),
                          style: const TextStyle(color: Color(0xFF0369A1), fontSize: 11),
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
    );
  }

  Widget _buildSelectedEntityInspector() {
    final entity = _controller.selectedEntity;
    if (entity == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFEF4444)),
            ),
            child: Text(
              entity.label,
              style: const TextStyle(color: Color(0xFFDC2626), fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),

          // Contextual controls based on entity type
          if (entity is VectorCadRect) ...[
            Text('W: ${entity.width.toStringAsFixed(1)} mm', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
            const SizedBox(width: 4),
            _buildInspectorMiniBtn('-10', () {
              final newW = (entity.width - 10.0).clamp(10.0, 5000.0);
              _controller.updateSelectedProperties(width: newW);
              if (_controller.liveSyncTo3d) _controller.syncToViewModel(widget.viewModel);
            }),
            _buildInspectorMiniBtn('+10', () {
              _controller.updateSelectedProperties(width: entity.width + 10.0);
              if (_controller.liveSyncTo3d) _controller.syncToViewModel(widget.viewModel);
            }),
            const SizedBox(width: 12),
            Text('H: ${entity.height.toStringAsFixed(1)} mm', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
            const SizedBox(width: 4),
            _buildInspectorMiniBtn('-10', () {
              final newH = (entity.height - 10.0).clamp(10.0, 5000.0);
              _controller.updateSelectedProperties(height: newH);
              if (_controller.liveSyncTo3d) _controller.syncToViewModel(widget.viewModel);
            }),
            _buildInspectorMiniBtn('+10', () {
              _controller.updateSelectedProperties(height: entity.height + 10.0);
              if (_controller.liveSyncTo3d) _controller.syncToViewModel(widget.viewModel);
            }),
          ] else if (entity is VectorCadLine) ...[
            Text('L: ${entity.length.toStringAsFixed(1)} mm', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
            const SizedBox(width: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: (entity.role == 'bend' || entity.isDashed) ? const Color(0xFFF59E0B) : const Color(0xFF0284C7),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                elevation: 0,
              ),
              onPressed: () {
                _controller.toggleSelectedBendLine();
                if (_controller.liveSyncTo3d) _controller.syncToViewModel(widget.viewModel);
              },
              child: Text(
                (entity.role == 'bend' || entity.isDashed) ? 'Role: Fold Bend' : 'Role: Cut Contour',
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
              ),
            ),
            if (entity.role == 'bend' || entity.isDashed) ...[
              const SizedBox(width: 12),
              Text('Angle: ${entity.bendAngleDeg.toStringAsFixed(0)}°', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
              const SizedBox(width: 4),
              _buildInspectorMiniBtn('-15°', () {
                final newAng = (entity.bendAngleDeg - 15.0).clamp(15.0, 165.0);
                _controller.updateSelectedProperties(bendAngleDeg: newAng);
                if (_controller.liveSyncTo3d) _controller.syncToViewModel(widget.viewModel);
              }),
              _buildInspectorMiniBtn('+15°', () {
                final newAng = (entity.bendAngleDeg + 15.0).clamp(15.0, 165.0);
                _controller.updateSelectedProperties(bendAngleDeg: newAng);
                if (_controller.liveSyncTo3d) _controller.syncToViewModel(widget.viewModel);
              }),
              const SizedBox(width: 8),
              _buildInspectorMiniBtn(entity.bendDirection, () {
                final newDir = entity.bendDirection == 'UP' ? 'DOWN' : 'UP';
                _controller.updateSelectedProperties(bendDirection: newDir);
                if (_controller.liveSyncTo3d) _controller.syncToViewModel(widget.viewModel);
              }),
            ],
          ] else if (entity is VectorCadCircle) ...[
            Text('Ø: ${entity.diameter.toStringAsFixed(1)} mm', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
            const SizedBox(width: 4),
            _buildInspectorMiniBtn('-5', () {
              final newR = (entity.radius - 2.5).clamp(2.0, 500.0);
              _controller.updateSelectedProperties(radius: newR);
              if (_controller.liveSyncTo3d) _controller.syncToViewModel(widget.viewModel);
            }),
            _buildInspectorMiniBtn('+5', () {
              _controller.updateSelectedProperties(radius: entity.radius + 2.5);
              if (_controller.liveSyncTo3d) _controller.syncToViewModel(widget.viewModel);
            }),
            const SizedBox(width: 12),
            Text('Role: ${entity.punchRole}', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
          ],
        ],
      ),
    );
  }

  Widget _buildInspectorMiniBtn(String text, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFE2E8F0),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFFCBD5E1)),
        ),
        child: Text(text, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
      ),
    );
  }

  Widget _buildMetricCol(String title, String val, Color valColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: const TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text(val, style: TextStyle(color: valColor, fontSize: 13, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildToolPill(VectorCadTool tool, String label) {
    final isActive = _controller.activeTool == tool;
    return InkWell(
      onTap: () => _controller.setActiveTool(tool),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF2563EB) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isActive ? const Color(0xFF1D4ED8) : const Color(0xFFCBD5E1)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : const Color(0xFF334155),
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  String _toolName(VectorCadTool tool) {
    switch (tool) {
      case VectorCadTool.select:
        return 'Select';
      case VectorCadTool.line:
        return 'Line';
      case VectorCadTool.rect:
        return 'Rectangle';
      case VectorCadTool.circle:
        return 'Circle';
    }
  }

  String _getTipText(VectorCadTool tool) {
    switch (tool) {
      case VectorCadTool.select:
        return 'Select element tool mode active: Click any vector geometry line on the drafting grid canvas above to inspect parameters or clear it.';
      case VectorCadTool.line:
        return 'Line drafting tool mode active: Click and drag on the drafting grid to draw linear sheet metal blank borders or bend lines.';
      case VectorCadTool.rect:
        return 'Box drafting tool mode active: Click and drag diagonally to draw a rectangular sheet metal plate, flange, or cutout.';
      case VectorCadTool.circle:
        return 'Circle drafting tool mode active: Click and drag outward to stamp circular punch bolt clearance holes.';
    }
  }
}
