// =============================================================================
// dxf_import_diagnostics_dialog.dart
//
// Modal review dialog for DXF Import Diagnostics per Step 9 (#22).
// Presents detected geometry entities, profile closure stats, and warnings,
// allowing the user to review before choosing "Heal & Import" or "Import Raw".
// =============================================================================

import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../engine/dxf_mini_parser.dart';
import '../../engine/dxf_import_diagnostics_engine.dart';

class DxfImportDiagnosticsDialog extends StatefulWidget {
  final DxfDiagnosticsReport report;
  final String fileName;
  final void Function(bool shouldHeal) onProceed;

  const DxfImportDiagnosticsDialog({
    super.key,
    required this.report,
    required this.fileName,
    required this.onProceed,
  });

  static Future<bool?> show(
    BuildContext context, {
    required DxfDiagnosticsReport report,
    required String fileName,
    void Function(bool shouldHeal)? onProceed,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DxfImportDiagnosticsDialog(
        report: report,
        fileName: fileName,
        onProceed: (shouldHeal) {
          onProceed?.call(shouldHeal);
        },
      ),
    );
  }

  @override
  State<DxfImportDiagnosticsDialog> createState() =>
      _DxfImportDiagnosticsDialogState();
}

class _DxfImportDiagnosticsDialogState
    extends State<DxfImportDiagnosticsDialog> {
  bool _removeDuplicates = true;
  bool _removeZeroLength = true;
  bool _healMicroGaps = true;

  Offset _dialogOffset = Offset.zero;
  late final TransformationController _previewTransformController;
  double _previewScale = 1.0;

  @override
  void initState() {
    super.initState();
    _previewTransformController = TransformationController();
    _previewTransformController.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _previewTransformController.removeListener(_onTransformChanged);
    _previewTransformController.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final scale = _previewTransformController.value.getMaxScaleOnAxis();
    if ((scale - _previewScale).abs() > 0.005) {
      setState(() {
        _previewScale = scale;
      });
    }
  }

  void _zoomAt(Offset focalPoint, double scaleFactor) {
    final currentMatrix = _previewTransformController.value;
    final currentScale = currentMatrix.getMaxScaleOnAxis();
    final targetScale = (currentScale * scaleFactor).clamp(0.2, 30.0);
    final effectiveFactor = targetScale / currentScale;
    if ((effectiveFactor - 1.0).abs() < 0.001) return;

    final translationToOrigin =
        Matrix4.translationValues(-focalPoint.dx, -focalPoint.dy, 0);
    final scaleMatrix =
        Matrix4.diagonal3Values(effectiveFactor, effectiveFactor, 1.0);
    final translationBack =
        Matrix4.translationValues(focalPoint.dx, focalPoint.dy, 0);

    final newMatrix = translationBack *
        scaleMatrix *
        translationToOrigin *
        currentMatrix;
    _previewTransformController.value = newMatrix;
  }

  void _zoomIn([Offset? center]) {
    _zoomAt(center ?? const Offset(270, 110), 1.25);
  }

  void _zoomOut([Offset? center]) {
    _zoomAt(center ?? const Offset(270, 110), 0.8);
  }

  void _resetZoom() {
    _previewTransformController.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Transform.translate(
        offset: _dialogOffset,
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          elevation: 16,
          shadowColor: Colors.black.withValues(alpha: 0.35),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Draggable Header
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanUpdate: (details) {
                              setState(() {
                                _dialogOffset += details.delta;
                              });
                            },
                            child: MouseRegion(
                              cursor: SystemMouseCursors.move,
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.fact_check_outlined,
                                      size: 24,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Text(
                                              'DXF Import Diagnostics',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF0F172A),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF1F5F9),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Row(
                                                mainAxisSize:
                                                    MainAxisSize.min,
                                                children: const [
                                                  Icon(
                                                    Icons.drag_indicator,
                                                    size: 13,
                                                    color: Color(0xFF94A3B8),
                                                  ),
                                                  SizedBox(width: 2),
                                                  Text(
                                                    'Drag',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      color: Color(0xFF64748B),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        Text(
                                          '${widget.fileName} • ${report.totalEntities} entities parsed',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            size: 20,
                            color: Color(0xFF94A3B8),
                          ),
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(context).pop(),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    const SizedBox(height: 16),

                // Feature Recognition Summary
                const Text(
                  'GEOMETRY & PROFILE SUMMARY',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 8),

                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildStatBadge(
                      icon: Icons.check_circle_outline,
                      color: const Color(0xFF16A34A),
                      label: '${report.closedProfilesCount} Closed Profiles',
                    ),
                    _buildStatBadge(
                      icon: Icons.view_agenda_outlined,
                      color: const Color(0xFF0284C7),
                      label: '${report.slotProfilesCount} Slot-like Profiles',
                    ),
                    _buildStatBadge(
                      icon: Icons.straighten,
                      color: const Color(0xFFD97706),
                      label: '${report.bendCandidatesCount} Bend Candidates',
                    ),
                    _buildStatBadge(
                      icon: Icons.layers_outlined,
                      color: const Color(0xFF64748B),
                      label: '${report.layersFound.length} CAD Layers',
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Visual Drawing Preview marking error locations
                _buildDrawingPreview(report),

                // Issues & Diagnostics
                if (report.hasIssues) ...[
                  const Text(
                    'HEALTH CHECKS & WARNINGS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: Color(0xFFEF4444),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Column(
                      children: report.warnings
                          .map(
                            (w) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.warning_amber_rounded,
                                    size: 16,
                                    color: Color(0xFFDC2626),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      w,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF991B1B),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Healing Options
                  const Text(
                    'AUTOMATIC HEALING OPTIONS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: _removeDuplicates,
                    title: const Text(
                      'Remove duplicate lines & arcs',
                      style: TextStyle(fontSize: 12),
                    ),
                    onChanged: (v) =>
                        setState(() => _removeDuplicates = v ?? true),
                  ),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: _removeZeroLength,
                    title: const Text(
                      'Prune zero-length entities (< 0.01 mm)',
                      style: TextStyle(fontSize: 12),
                    ),
                    onChanged: (v) =>
                        setState(() => _removeZeroLength = v ?? true),
                  ),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: _healMicroGaps,
                    title: const Text(
                      'Heal endpoint micro-gaps (< 0.5 mm) to close loops',
                      style: TextStyle(fontSize: 12),
                    ),
                    onChanged: (v) =>
                        setState(() => _healMicroGaps = v ?? true),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFBBF7D0)),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.verified,
                          size: 18,
                          color: Color(0xFF16A34A),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Zero geometry errors detected. Profiles, bend lines and layers are fully intact.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF166534),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // Action Buttons
                Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: Color(0xFF64748B)),
                      ),
                    ),
                    if (report.hasIssues)
                      OutlinedButton(
                        onPressed: () {
                          widget.onProceed(false);
                          Navigator.of(context).pop(false);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF334155),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                        ),
                        child: const Text('Import Raw As-Is'),
                      ),
                    ElevatedButton.icon(
                      onPressed: () {
                        widget.onProceed(report.hasIssues);
                        Navigator.of(context).pop(report.hasIssues);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: report.hasIssues
                            ? const Color(0xFF0284C7)
                            : const Color(0xFF16A34A),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      icon: Icon(
                        report.hasIssues
                            ? Icons.auto_fix_high
                            : Icons.check_circle_outline,
                        size: 16,
                      ),
                      label: Text(
                        report.hasIssues ? 'Heal & Import' : 'Import',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  ),
);
}

  Widget _buildStatBadge({
    required IconData icon,
    required Color color,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawingPreview(DxfDiagnosticsReport report) {
    if (report.parsedData == null || report.parsedData!.entities.isEmpty) {
      return const SizedBox.shrink();
    }

    final hasErrors = report.errorLocations.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Text(
                'DXF DRAWING PREVIEW & ERROR LOCATIONS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: Color(0xFF64748B),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            if (hasErrors)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 12, color: Color(0xFFDC2626)),
                    const SizedBox(width: 4),
                    Text(
                      '${report.errorLocations.length} Error Points Marked in Red',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF86EFAC)),
                ),
                child: const Text(
                  'All Geometry Closed & Valid',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF16A34A)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            final previewWidth = constraints.maxWidth;
            const previewHeight = 220.0;
            final centerOffset = Offset(previewWidth / 2, previewHeight / 2);

            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: previewHeight,
                width: previewWidth,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Stack(
                  children: [
                    // Fixed background drafting grid
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _DxfDraftingGridPainter(),
                      ),
                    ),

                    // Interactive Zoom & Pan Area
                    Positioned.fill(
                      child: Listener(
                        onPointerSignal: (pointerSignal) {
                          if (pointerSignal is PointerScrollEvent) {
                            GestureBinding.instance.pointerSignalResolver.register(
                              pointerSignal,
                              (event) {
                                final scrollEvent = event as PointerScrollEvent;
                                final factor =
                                    scrollEvent.scrollDelta.dy < 0 ? 1.15 : 0.87;
                                _zoomAt(scrollEvent.localPosition, factor);
                              },
                            );
                          }
                        },
                        child: InteractiveViewer(
                          transformationController: _previewTransformController,
                          minScale: 0.2,
                          maxScale: 30.0,
                          boundaryMargin: const EdgeInsets.all(350),
                          clipBehavior: Clip.none,
                          child: SizedBox(
                            width: previewWidth,
                            height: previewHeight,
                            child: CustomPaint(
                              painter: _DxfDiagnosticCanvasPainter(
                                parsed: report.parsedData,
                                errorLocations: report.errorLocations,
                                currentScale: _previewScale,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Floating Zoom Controls (Top Right)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xDD0F172A),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              child: Text(
                                '${(_previewScale * 100).round()}%',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 14,
                              color: const Color(0xFF334155),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.add,
                                size: 14,
                                color: Color(0xFFE2E8F0),
                              ),
                              tooltip: 'Zoom In',
                              constraints: const BoxConstraints(
                                minWidth: 26,
                                minHeight: 26,
                              ),
                              padding: EdgeInsets.zero,
                              onPressed: () => _zoomIn(centerOffset),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.remove,
                                size: 14,
                                color: Color(0xFFE2E8F0),
                              ),
                              tooltip: 'Zoom Out',
                              constraints: const BoxConstraints(
                                minWidth: 26,
                                minHeight: 26,
                              ),
                              padding: EdgeInsets.zero,
                              onPressed: () => _zoomOut(centerOffset),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.fit_screen,
                                size: 14,
                                color: Color(0xFF38BDF8),
                              ),
                              tooltip: 'Reset View / Fit',
                              constraints: const BoxConstraints(
                                minWidth: 26,
                                minHeight: 26,
                              ),
                              padding: EdgeInsets.zero,
                              onPressed: _resetZoom,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Interaction Hint (Bottom Left)
                    Positioned(
                      bottom: 6,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xCC0F172A),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(
                              Icons.mouse_outlined,
                              size: 11,
                              color: Color(0xFF64748B),
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Scroll to zoom • Drag to pan',
                              style: TextStyle(
                                fontSize: 9,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Legend (Bottom Right)
                    Positioned(
                      bottom: 6,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xCC0F172A),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Text(
                              '— Geometry  ',
                              style: TextStyle(
                                fontSize: 9,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                            Text(
                              '--- Bend  ',
                              style: TextStyle(
                                fontSize: 9,
                                color: Color(0xFF06B6D4),
                              ),
                            ),
                            Text(
                              '⦻ Error Location',
                              style: TextStyle(
                                fontSize: 9,
                                color: Color(0xFFF87171),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _DxfDraftingGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..strokeWidth = 0.8;
    const step = 20.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DxfDiagnosticCanvasPainter extends CustomPainter {
  final DxfParsedData? parsed;
  final List<DxfDiagnosticErrorLocation> errorLocations;
  final double currentScale;

  _DxfDiagnosticCanvasPainter({
    required this.parsed,
    required this.errorLocations,
    this.currentScale = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (parsed == null || parsed!.entities.isEmpty) {
      return;
    }

    // 1. Calculate bounding box of entities
    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;

    void expand(double x, double y) {
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }

    for (final e in parsed!.entities) {
      if (e is DxfRawLine) {
        expand(e.p1.x, e.p1.y);
        expand(e.p2.x, e.p2.y);
      } else if (e is DxfRawPolyline) {
        for (final v in e.vertices) {
          expand(v.x, v.y);
        }
      } else if (e is DxfRawCircle) {
        expand(e.center.x - e.radius, e.center.y - e.radius);
        expand(e.center.x + e.radius, e.center.y + e.radius);
      } else if (e is DxfRawArc) {
        expand(e.center.x - e.radius, e.center.y - e.radius);
        expand(e.center.x + e.radius, e.center.y + e.radius);
      }
    }

    if (minX == double.infinity || maxX == -double.infinity) return;

    final geomW = math.max(1.0, maxX - minX);
    final geomH = math.max(1.0, maxY - minY);

    const padding = 20.0;
    final availW = math.max(10.0, size.width - padding * 2);
    final availH = math.max(10.0, size.height - padding * 2);

    final scale = math.min(availW / geomW, availH / geomH);

    final offsetX = padding + (availW - geomW * scale) / 2.0;
    final offsetY = padding + (availH - geomH * scale) / 2.0;

    // DXF Y is inverted compared to screen (CAD Y points up)
    Offset toScreen(double cadX, double cadY) {
      final sx = offsetX + (cadX - minX) * scale;
      final sy = size.height - (offsetY + (cadY - minY) * scale);
      return Offset(sx, sy);
    }

    final effectiveScale = math.max(0.4, currentScale);

    final geomPaint = Paint()
      ..color = const Color(0xFF94A3B8)
      ..strokeWidth = 1.2 / effectiveScale
      ..style = PaintingStyle.stroke;

    final bendPaint = Paint()
      ..color = const Color(0xFF06B6D4)
      ..strokeWidth = 1.4 / effectiveScale
      ..style = PaintingStyle.stroke;

    final circlePaint = Paint()
      ..color = const Color(0xFF38BDF8)
      ..strokeWidth = 1.2 / effectiveScale
      ..style = PaintingStyle.stroke;

    // Draw entities
    for (final e in parsed!.entities) {
      if (e is DxfRawLine) {
        final p1 = toScreen(e.p1.x, e.p1.y);
        final p2 = toScreen(e.p2.x, e.p2.y);
        final isBend = e.layer.toLowerCase().contains('bend') ||
            e.layer.toLowerCase().contains('fold') ||
            e.colorIndex == 4 ||
            e.colorIndex == 2;
        canvas.drawLine(p1, p2, isBend ? bendPaint : geomPaint);
      } else if (e is DxfRawPolyline) {
        if (e.vertices.length >= 2) {
          final path = Path();
          final start = toScreen(e.vertices.first.x, e.vertices.first.y);
          path.moveTo(start.dx, start.dy);
          for (int i = 1; i < e.vertices.length; i++) {
            final pt = toScreen(e.vertices[i].x, e.vertices[i].y);
            path.lineTo(pt.dx, pt.dy);
          }
          if (e.isClosed) {
            path.close();
          }
          canvas.drawPath(path, geomPaint);
        }
      } else if (e is DxfRawCircle) {
        final c = toScreen(e.center.x, e.center.y);
        canvas.drawCircle(c, e.radius * scale, circlePaint);
      } else if (e is DxfRawArc) {
        final c = toScreen(e.center.x, e.center.y);
        final r = e.radius * scale;
        final rect = Rect.fromCircle(center: c, radius: r);
        final startRad = -e.startAngleDeg * (math.pi / 180.0);
        double sweepDeg = e.endAngleDeg - e.startAngleDeg;
        if (sweepDeg < 0) sweepDeg += 360.0;
        final sweepRad = -sweepDeg * (math.pi / 180.0);
        canvas.drawArc(rect, startRad, sweepRad, false, circlePaint);
      }
    }

    // 2. Mark Error Locations
    final errRingPaint = Paint()
      ..color = const Color(0xFFEF4444)
      ..strokeWidth = 2.0 / effectiveScale
      ..style = PaintingStyle.stroke;

    final errHaloPaint = Paint()
      ..color = const Color(0x40EF4444)
      ..style = PaintingStyle.fill;

    final errCrossPaint = Paint()
      ..color = const Color(0xFFFCA5A5)
      ..strokeWidth = 1.5 / effectiveScale;

    final ringRadius = 6.0 / effectiveScale;
    final haloRadius = 11.0 / effectiveScale;
    final crossSize = 3.5 / effectiveScale;

    for (final err in errorLocations) {
      final sp = toScreen(err.point.x, err.point.y);

      // Outer glow halo
      canvas.drawCircle(sp, haloRadius, errHaloPaint);

      // Distinct target circle
      canvas.drawCircle(sp, ringRadius, errRingPaint);

      // Red crosshair ✕
      canvas.drawLine(
        Offset(sp.dx - crossSize, sp.dy - crossSize),
        Offset(sp.dx + crossSize, sp.dy + crossSize),
        errCrossPaint,
      );
      canvas.drawLine(
        Offset(sp.dx + crossSize, sp.dy - crossSize),
        Offset(sp.dx - crossSize, sp.dy + crossSize),
        errCrossPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DxfDiagnosticCanvasPainter oldDelegate) {
    return oldDelegate.parsed != parsed ||
        oldDelegate.errorLocations != errorLocations ||
        oldDelegate.currentScale != currentScale;
  }
}
