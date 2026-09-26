// =============================================================================
// dds_paper_canvas.dart
//
// Technical Data Sheet (TDS) Paper Canvas & ISO 7200 Presentation Renderer.
// Renders standard ISO 5457 / ISO 7200 compliant A4/A3 engineering submittal sheets.
//
// Features:
// 1. Two distinct sheet formats:
//    - Cover Schedule Sheet: Submittal transmittal, project control grid,
//      complete Product Schedule table (from Excel / DDS instances), and
//      client approval sign-off stamps.
//    - Product Sheet: Split viewports with 2D dimensioned flat pattern and
//      3D isometric preview (base + live exploded/snapped cover), key dimensions,
//      and docked ISO 7200 title block.
// 2. Interactive paper container with zoom/pan and crisp physical borders.
// 3. Interactive Markup & Annotation Overlay:
//    - Linear dimensions with CAD arrows and witness lines.
//    - Leader notes pointing to features with callouts.
//    - Note boxes, revision clouds with Δ1 tags, and approval stamps.
// =============================================================================

import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../engine/kinematic_fold_engine.dart';
import '../../../models/cad_primitives.dart';
import '../../../models/dds/dds_annotation.dart';
import '../../../models/dds/dds_document.dart';
import '../../../models/dds/dds_product_instance.dart';
import '../../../models/dds/dds_sheet.dart';
import '../../../engine/dds/dds_instance_evaluator.dart';
import 'dds_drawing_painters.dart';

enum DdsViewportMode {
  transitionWipe,
  split,
  kinematicFold,
}

class DdsPaperCanvas extends StatefulWidget {
  final DdsDocument document;
  final DdsSheet sheet;
  final EvaluatedDdsInstance? evaluatedInstance;
  final DdsMarkupTool activeMarkupTool;
  final String? selectedAnnotationId;
  final void Function(List<DdsAnnotation> updatedAnnotations)? onAnnotationsChanged;
  final void Function(String? annotationId)? onAnnotationSelected;
  final VoidCallback? onNextSheet;
  final VoidCallback? onPrevSheet;

  const DdsPaperCanvas({
    super.key,
    required this.document,
    required this.sheet,
    this.evaluatedInstance,
    this.activeMarkupTool = DdsMarkupTool.select,
    this.selectedAnnotationId,
    this.onAnnotationsChanged,
    this.onAnnotationSelected,
    this.onNextSheet,
    this.onPrevSheet,
  });

  @override
  State<DdsPaperCanvas> createState() => _DdsPaperCanvasState();
}

class _DdsPaperCanvasState extends State<DdsPaperCanvas> with TickerProviderStateMixin {
  // Temporary interactive drawing state
  CadPoint2D? _pendingStartPoint;
  CadPoint2D? _currentHoverPoint;
  final List<CadPoint2D> _pendingCloudPoints = [];

  // Hit test radius in sheet mm
  static const double _hitTestRadiusMm = 8.0;

  // Viewport mode and 2D/3D transition parameters
  DdsViewportMode _viewportMode = DdsViewportMode.transitionWipe;
  double _transitionProgress = 0.50; // 0.0 to 1.0 (sweep divider line)
  bool _showHatching = true;
  bool _isAutoSweeping = false;
  late AnimationController _sweepController;

  // Kinematic fold simulation parameters
  double _foldProgress = 1.0; // 0.0 (flat sheet) to 1.0 (folded 90 deg channel)
  bool _isAutoFolding = false;
  late AnimationController _foldController;

  @override
  void initState() {
    super.initState();
    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    )..addListener(() {
        if (_isAutoSweeping) {
          setState(() {
            _transitionProgress = _sweepController.value;
          });
        }
      });

    _foldController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..addListener(() {
        if (_isAutoFolding) {
          setState(() {
            _foldProgress = _foldController.value;
          });
        }
      });
  }

  @override
  void dispose() {
    _sweepController.dispose();
    _foldController.dispose();
    super.dispose();
  }

  void _toggleAutoSweep() {
    setState(() {
      _isAutoSweeping = !_isAutoSweeping;
      if (_isAutoSweeping) {
        _sweepController.repeat(reverse: true);
      } else {
        _sweepController.stop();
      }
    });
  }

  void _toggleAutoFold() {
    setState(() {
      _isAutoFolding = !_isAutoFolding;
      if (_isAutoFolding) {
        _foldController.repeat(reverse: true);
      } else {
        _foldController.stop();
      }
    });
  }

  @override
  void didUpdateWidget(covariant DdsPaperCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeMarkupTool != widget.activeMarkupTool) {
      _pendingStartPoint = null;
      _pendingCloudPoints.clear();
      _currentHoverPoint = null;
    }
  }

  // ===========================================================================
  // Interactive Pointer Gestures for Markup Authoring
  // ===========================================================================

  void _handlePointerHover(PointerHoverEvent event, Size paperSize) {
    if (paperSize.width <= 0 || paperSize.height <= 0) return;
    final mmX = (event.localPosition.dx / paperSize.width) * 297.0;
    final mmY = (event.localPosition.dy / paperSize.height) * 210.0;
    setState(() {
      _currentHoverPoint = CadPoint2D(mmX, mmY);
    });
  }

  void _handlePointerDown(PointerDownEvent event, Size paperSize) {
    if (paperSize.width <= 0 || paperSize.height <= 0) return;
    final mmX = (event.localPosition.dx / paperSize.width) * 297.0;
    final mmY = (event.localPosition.dy / paperSize.height) * 210.0;
    final clickPoint = CadPoint2D(mmX, mmY);

    switch (widget.activeMarkupTool) {
      case DdsMarkupTool.select:
        _performHitTest(clickPoint);
        break;

      case DdsMarkupTool.linearDimension:
        if (_pendingStartPoint == null) {
          setState(() => _pendingStartPoint = clickPoint);
        } else {
          final p1 = _pendingStartPoint!;
          final p2 = clickPoint;
          _pendingStartPoint = null;
          _createLinearDimension(p1, p2);
        }
        break;

      case DdsMarkupTool.leaderNote:
        if (_pendingStartPoint == null) {
          setState(() => _pendingStartPoint = clickPoint);
        } else {
          final target = _pendingStartPoint!;
          final textPos = clickPoint;
          _pendingStartPoint = null;
          _promptAndCreateLeaderNote(target, textPos);
        }
        break;

      case DdsMarkupTool.noteBox:
        _promptAndCreateNoteBox(clickPoint);
        break;

      case DdsMarkupTool.revisionCloud:
        setState(() {
          _pendingCloudPoints.add(clickPoint);
        });
        break;

      case DdsMarkupTool.approvalStamp:
        _createApprovalStamp(clickPoint);
        break;
    }
  }

  void _performHitTest(CadPoint2D clickMm) {
    for (final ann in widget.sheet.annotations.reversed) {
      if (!ann.isVisible) continue;

      if (ann is DdsLinearDimensionAnnotation) {
        final d1 = (ann.p1 - clickMm).length;
        final d2 = (ann.p2 - clickMm).length;
        final mid = CadPoint2D((ann.p1.x + ann.p2.x) / 2, (ann.p1.y + ann.p2.y) / 2);
        final dMid = (mid - clickMm).length;
        if (d1 < _hitTestRadiusMm || d2 < _hitTestRadiusMm || dMid < _hitTestRadiusMm) {
          widget.onAnnotationSelected?.call(ann.id);
          return;
        }
      } else if (ann is DdsLeaderNoteAnnotation) {
        final dT = (ann.targetPoint - clickMm).length;
        final dP = (ann.textPosition - clickMm).length;
        if (dT < _hitTestRadiusMm || dP < _hitTestRadiusMm) {
          widget.onAnnotationSelected?.call(ann.id);
          return;
        }
      } else if (ann is DdsNoteBoxAnnotation) {
        if (clickMm.x >= ann.x &&
            clickMm.x <= ann.x + ann.width &&
            clickMm.y >= ann.y &&
            clickMm.y <= ann.y + ann.height) {
          widget.onAnnotationSelected?.call(ann.id);
          return;
        }
      } else if (ann is DdsApprovalStampAnnotation) {
        if (clickMm.x >= ann.x &&
            clickMm.x <= ann.x + ann.width &&
            clickMm.y >= ann.y &&
            clickMm.y <= ann.y + ann.height) {
          widget.onAnnotationSelected?.call(ann.id);
          return;
        }
      } else if (ann is DdsRevisionCloudAnnotation) {
        for (final pt in ann.points) {
          if ((pt - clickMm).length < _hitTestRadiusMm) {
            widget.onAnnotationSelected?.call(ann.id);
            return;
          }
        }
      }
    }

    // Deselect if clicked blank area
    widget.onAnnotationSelected?.call(null);
  }

  void _createLinearDimension(CadPoint2D p1, CadPoint2D p2) {
    final length = (p2 - p1).length;
    final annotation = DdsLinearDimensionAnnotation(
      id: 'dim_${DateTime.now().millisecondsSinceEpoch}',
      p1: p1,
      p2: p2,
      prefix: 'L = ',
      suffix: ' mm',
      offsetDistance: 12.0,
      textOverride: '${length.toStringAsFixed(1)} mm',
    );

    final list = List<DdsAnnotation>.from(widget.sheet.annotations)..add(annotation);
    widget.onAnnotationsChanged?.call(list);
    widget.onAnnotationSelected?.call(annotation.id);
  }

  Future<void> _promptAndCreateLeaderNote(CadPoint2D target, CadPoint2D textPos) async {
    final controller = TextEditingController(text: 'Coupler Flap (4x M6 Slots)');
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Row(
          children: [
            Icon(Icons.call_made, color: Color(0xFF38BDF8), size: 18),
            SizedBox(width: 8.0),
            Text('Leader Callout Note', style: TextStyle(color: Colors.white, fontSize: 14.0)),
          ],
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 13.0),
          decoration: InputDecoration(
            labelText: 'Note Text',
            labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
            filled: true,
            fillColor: const Color(0xFF0F172A),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6.0)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Place Note', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (text == null || text.isEmpty) return;

    final annotation = DdsLeaderNoteAnnotation(
      id: 'leader_${DateTime.now().millisecondsSinceEpoch}',
      targetPoint: target,
      textPosition: textPos,
      text: text,
    );

    final list = List<DdsAnnotation>.from(widget.sheet.annotations)..add(annotation);
    widget.onAnnotationsChanged?.call(list);
    widget.onAnnotationSelected?.call(annotation.id);
  }

  Future<void> _promptAndCreateNoteBox(CadPoint2D pos) async {
    final controller = TextEditingController(
      text: 'NOTE: All dimensions in mm. Confirm site opening before fabrication.',
    );
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Row(
          children: [
            Icon(Icons.note_alt_outlined, color: Color(0xFF38BDF8), size: 18),
            SizedBox(width: 8.0),
            Text('General Sheet Note', style: TextStyle(color: Colors.white, fontSize: 14.0)),
          ],
        ),
        content: TextField(
          controller: controller,
          maxLines: 3,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 13.0),
          decoration: InputDecoration(
            labelText: 'Specification / Site Note',
            labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
            filled: true,
            fillColor: const Color(0xFF0F172A),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6.0)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Add Note Box', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (text == null || text.isEmpty) return;

    final annotation = DdsNoteBoxAnnotation(
      id: 'notebox_${DateTime.now().millisecondsSinceEpoch}',
      x: pos.x,
      y: pos.y,
      width: 75.0,
      height: 25.0,
      text: text,
    );

    final list = List<DdsAnnotation>.from(widget.sheet.annotations)..add(annotation);
    widget.onAnnotationsChanged?.call(list);
    widget.onAnnotationSelected?.call(annotation.id);
  }

  void _finishRevisionCloud() {
    if (_pendingCloudPoints.length < 2) {
      setState(() => _pendingCloudPoints.clear());
      return;
    }

    final annotation = DdsRevisionCloudAnnotation(
      id: 'revcloud_${DateTime.now().millisecondsSinceEpoch}',
      points: List<CadPoint2D>.from(_pendingCloudPoints),
      revisionTag: 'Δ${widget.document.projectInfo.revision}',
    );

    _pendingCloudPoints.clear();
    final list = List<DdsAnnotation>.from(widget.sheet.annotations)..add(annotation);
    widget.onAnnotationsChanged?.call(list);
    widget.onAnnotationSelected?.call(annotation.id);
  }

  void _createApprovalStamp(CadPoint2D pos) {
    final annotation = DdsApprovalStampAnnotation(
      id: 'stamp_${DateTime.now().millisecondsSinceEpoch}',
      x: pos.x,
      y: pos.y,
      width: 70.0,
      height: 28.0,
      status: 'APPROVED AS NOTED',
      reviewedBy: widget.document.projectInfo.consultant.isNotEmpty
          ? widget.document.projectInfo.consultant
          : 'Consultant Engineer',
      reviewDate: widget.document.projectInfo.issueDate,
    );

    final list = List<DdsAnnotation>.from(widget.sheet.annotations)..add(annotation);
    widget.onAnnotationsChanged?.call(list);
    widget.onAnnotationSelected?.call(annotation.id);
  }

  void _deleteSelectedAnnotation() {
    if (widget.selectedAnnotationId == null) return;
    final list = widget.sheet.annotations.where((a) => a.id != widget.selectedAnnotationId).toList();
    widget.onAnnotationsChanged?.call(list);
    widget.onAnnotationSelected?.call(null);
  }

  // ===========================================================================
  // Build Method
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const paperAspect = 297.0 / 210.0;
        final maxWidth = constraints.maxWidth - 32.0;
        final maxHeight = constraints.maxHeight - 32.0;

        double paperWidth = maxWidth;
        double paperHeight = paperWidth / paperAspect;

        if (paperHeight > maxHeight) {
          paperHeight = maxHeight;
          paperWidth = paperHeight * paperAspect;
        }

        final paperSize = Size(paperWidth, paperHeight);

        return Center(
          child: MouseRegion(
            onHover: (e) => _handlePointerHover(e, paperSize),
            cursor: _getCursorForMarkupTool(),
            child: Listener(
              onPointerDown: (e) => _handlePointerDown(e, paperSize),
              child: Container(
                width: paperWidth,
                height: paperHeight,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4.0),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 16.0,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    // Physical Sheet Content (Cover or Product Layout)
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20.0, 10.0, 10.0, 10.0), // 20mm filing margin
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFF0F172A), width: 1.2),
                          ),
                          child: widget.sheet.isCoverPage
                              ? _buildCoverPageSheet()
                              : _buildProductSheet(),
                        ),
                      ),
                    ),

                    // Interactive Annotation Layer (Linear dimensions, leader notes, clouds, stamps)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _DdsAnnotationOverlayPainter(
                          annotations: widget.sheet.annotations,
                          selectedAnnotationId: widget.selectedAnnotationId,
                          paperSize: paperSize,
                          pendingStartPoint: _pendingStartPoint,
                          hoverPoint: _currentHoverPoint,
                          pendingCloudPoints: _pendingCloudPoints,
                          activeTool: widget.activeMarkupTool,
                        ),
                      ),
                    ),

                    // Revision Cloud "Finish Cloud" floating button
                    if (_pendingCloudPoints.length >= 2 && widget.activeMarkupTool == DdsMarkupTool.revisionCloud)
                      Positioned(
                        bottom: 16,
                        right: 16,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
                          icon: const Icon(Icons.check, size: 16, color: Colors.white),
                          label: const Text('Finish Cloud', style: TextStyle(color: Colors.white, fontSize: 12.0)),
                          onPressed: _finishRevisionCloud,
                        ),
                      ),

                    // Quick Delete Floating Button for Selected Annotation
                    if (widget.selectedAnnotationId != null)
                      Positioned(
                        top: 16,
                        right: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(6.0),
                            border: Border.all(color: const Color(0xFFEF4444)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Markup Selected', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.0)),
                              const SizedBox(width: 8.0),
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: EdgeInsets.zero,
                                icon: const Icon(Icons.delete, color: Color(0xFFEF4444), size: 16),
                                tooltip: 'Delete Annotation',
                                onPressed: _deleteSelectedAnnotation,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  MouseCursor _getCursorForMarkupTool() {
    switch (widget.activeMarkupTool) {
      case DdsMarkupTool.select:
        return SystemMouseCursors.click;
      case DdsMarkupTool.linearDimension:
      case DdsMarkupTool.leaderNote:
      case DdsMarkupTool.revisionCloud:
        return SystemMouseCursors.precise;
      case DdsMarkupTool.noteBox:
      case DdsMarkupTool.approvalStamp:
        return SystemMouseCursors.copy;
    }
  }

  // ===========================================================================
  // 1. Cover Schedule Sheet Layout
  // ===========================================================================

  Widget _buildCoverPageSheet() {
    final proj = widget.document.projectInfo;
    final toc = widget.sheet.tableOfContents;

    return Column(
      children: [
        // Submittal Transmittal Header
        Container(
          padding: const EdgeInsets.all(12.0),
          decoration: const BoxDecoration(
            color: Color(0xFF0F172A),
            border: Border(bottom: BorderSide(color: Color(0xFF0F172A), width: 1.2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    proj.documentTitle.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.0,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2.0),
                  Text(
                    'SUBMITTAL TRANSMITTAL & PRODUCT SCHEDULE  •  DOC: ${proj.documentNumber}',
                    style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 9.5, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7),
                  borderRadius: BorderRadius.circular(4.0),
                ),
                child: Text(
                  'REV ${proj.revision}  (${proj.status.toUpperCase()})',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10.5),
                ),
              ),
            ],
          ),
        ),

        // Document Control Grid (ISO 7200)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          color: const Color(0xFFF1F5F9),
          child: Row(
            children: [
              Expanded(child: _buildMetaField('PROJECT', proj.projectName)),
              Expanded(child: _buildMetaField('CLIENT', proj.client)),
              Expanded(child: _buildMetaField('CONSULTANT', proj.consultant)),
              Expanded(child: _buildMetaField('CONTRACTOR', proj.contractor)),
              Expanded(child: _buildMetaField('DATE', proj.issueDate)),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFCBD5E1)),

        // Table of Contents & BoQ Schedule Table
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.format_list_numbered, size: 14, color: Color(0xFF0284C7)),
                    SizedBox(width: 6.0),
                    Text(
                      'PRODUCT TRANSMITTAL SCHEDULE & BILL OF QUANTITIES',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8.0),

                // Table Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
                  color: const Color(0xFFE2E8F0),
                  child: const Row(
                    children: [
                      SizedBox(width: 36, child: Text('SHEET', style: _tocHeaderStyle)),
                      SizedBox(width: 50, child: Text('LINE #', style: _tocHeaderStyle)),
                      SizedBox(width: 80, child: Text('CUSTOMER REF', style: _tocHeaderStyle)),
                      Expanded(flex: 4, child: Text('PRODUCT DESCRIPTION', style: _tocHeaderStyle)),
                      Expanded(flex: 3, child: Text('CONFIGURATION & PORTS', style: _tocHeaderStyle)),
                      SizedBox(width: 44, child: Text('QTY', style: _tocHeaderStyle, textAlign: TextAlign.right)),
                      SizedBox(width: 60, child: Text('STATUS', style: _tocHeaderStyle, textAlign: TextAlign.center)),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFF94A3B8)),

                // Table Rows
                Expanded(
                  child: ListView.separated(
                    itemCount: toc.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    itemBuilder: (context, idx) {
                      final item = toc[idx];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 5.0),
                        child: Row(
                          children: [
                            SizedBox(width: 36, child: Text(item.sheetNumber.toString().padLeft(2, '0'), style: _tocRowStyleBold)),
                            SizedBox(width: 50, child: Text(item.orderLine, style: _tocRowStyle)),
                            SizedBox(width: 80, child: Text(item.customerRef, style: _tocRowStyleBold)),
                            Expanded(flex: 4, child: Text(item.productName, style: _tocRowStyleBold)),
                            Expanded(flex: 3, child: Text(item.configuration, style: _tocRowStyle)),
                            SizedBox(width: 44, child: Text('${item.quantity} pcs', style: _tocRowStyle, textAlign: TextAlign.right)),
                            SizedBox(
                              width: 60,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(3.0),
                                    border: Border.all(color: const Color(0xFF10B981), width: 0.6),
                                  ),
                                  child: Text(
                                    item.status.toUpperCase(),
                                    style: const TextStyle(color: Color(0xFF047857), fontSize: 8.0, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),

        // Compliance Notes & Client Approval Stamp Block
        Container(
          padding: const EdgeInsets.all(12.0),
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            border: Border(top: BorderSide(color: Color(0xFF0F172A), width: 1.2)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // General Specifications & Compliance
              const Expanded(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('GENERAL NOTES & COMPLIANCE:', style: TextStyle(fontSize: 9.0, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                    SizedBox(height: 3.0),
                    Text('1. Conforms to BS EN 50085-1: Cable trunking systems and cable ducting systems.', style: TextStyle(fontSize: 8.0, color: Color(0xFF475569))),
                    Text('2. Material: Pre-Galvanized Mild Steel DX51D + Z275 coating (nominal thickness 1.5 mm).', style: TextStyle(fontSize: 8.0, color: Color(0xFF475569))),
                    Text('3. Universal 95 mm coupler flap spacing with integral slotted holes (Ø6 mm).', style: TextStyle(fontSize: 8.0, color: Color(0xFF475569))),
                  ],
                ),
              ),

              // Client Approval Stamp
              Expanded(
                flex: 5,
                child: Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFF0284C7), width: 1.0),
                    borderRadius: BorderRadius.circular(4.0),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('CLIENT / CONSULTANT APPROVAL STAMP', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Color(0xFF0284C7))),
                          Text('ISO 7200', style: TextStyle(fontSize: 8.0, color: Color(0xFF64748B))),
                        ],
                      ),
                      SizedBox(height: 4.0),
                      Row(
                        children: [
                          Text('[  ] APPROVED    [  ] APPROVED AS NOTED    [  ] REVISE & RESUBMIT', style: TextStyle(fontSize: 7.5, color: Color(0xFF334155))),
                        ],
                      ),
                      SizedBox(height: 4.0),
                      Text('Signed: ___________________________    Date: ______________', style: TextStyle(fontSize: 8.0, color: Color(0xFF64748B))),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // 2. Product Detail Sheet Layout
  // ===========================================================================

  Widget _buildProductSheet() {
    final inst = widget.document.findInstance(widget.sheet.productInstanceId);
    final eval = widget.evaluatedInstance;

    return Column(
      children: [
        // Sheet Product Top Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          decoration: const BoxDecoration(
            color: Color(0xFF0F172A),
            border: Border(bottom: BorderSide(color: Color(0xFF0F172A), width: 1.2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    inst?.productName ?? widget.sheet.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7),
                      borderRadius: BorderRadius.circular(3.0),
                    ),
                    child: Text(
                      inst?.productCode ?? 'PRODUCT',
                      style: const TextStyle(color: Colors.white, fontSize: 9.0, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              if (inst?.orderLine != null)
                Text(
                  'ORDER: ${inst!.orderLine!.orderNumber}  |  LINE ${inst.orderLine!.lineNumber}  |  QTY: ${inst.orderLine!.quantity} PCS',
                  style: const TextStyle(
                    color: Color(0xFF38BDF8),
                    fontSize: 10.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
        ),

        // Viewport Mode & Animation Control Bar
        _buildViewportControlBar(eval),

        // Active Viewport (2D ⇄ 3D Transition Wipe, Kinematic Fold, or Dual Split)
        Expanded(
          child: _buildActiveViewport(eval),
        ),

        // Bottom Technical Strip + Docked ISO 7200 Title Block
        _buildProductBottomDock(inst, eval),
      ],
    );
  }

  // ===========================================================================
  // 2D ⇄ 3D Transition & Viewport Modes
  // ===========================================================================

  Widget _buildViewportControlBar(EvaluatedDdsInstance? eval) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 3.0),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        border: Border(bottom: BorderSide(color: Color(0xFF334155), width: 1.0)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: Viewport Mode Switcher
          Row(
            children: [
              _buildModeTab(
                mode: DdsViewportMode.transitionWipe,
                icon: Icons.compare_arrows,
                label: '2D ⇄ 3D Transition Wipe',
                badgeText: 'REEL FX',
              ),
              const SizedBox(width: 4),
              _buildModeTab(
                mode: DdsViewportMode.kinematicFold,
                icon: Icons.view_in_ar,
                label: 'Kinematic 3D Fold',
                badgeText: '${(_foldProgress * 90).toInt()}°',
              ),
              const SizedBox(width: 4),
              _buildModeTab(
                mode: DdsViewportMode.split,
                icon: Icons.vertical_split,
                label: 'Dual Split',
              ),
            ],
          ),

          // Right: Active Mode Controls
          if (_viewportMode == DdsViewportMode.transitionWipe)
            Row(
              children: [
                // 45 deg Mechanical Section Hatching Toggle
                InkWell(
                  onTap: () => setState(() => _showHatching = !_showHatching),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _showHatching ? const Color(0xFF0284C7).withValues(alpha: 0.2) : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: _showHatching ? const Color(0xFF38BDF8) : const Color(0xFF475569),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.texture,
                          size: 11,
                          color: _showHatching ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '45° Hatching',
                          style: TextStyle(
                            color: _showHatching ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8),
                            fontSize: 9.0,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // 50% Quick Reset
                InkWell(
                  onTap: () {
                    if (_isAutoSweeping) {
                      setState(() {
                        _isAutoSweeping = false;
                        _sweepController.stop();
                      });
                    }
                    setState(() => _transitionProgress = 0.50);
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF334155),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '50% Split',
                      style: TextStyle(color: Colors.white, fontSize: 9.0, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // Auto-Sweep Button (60 FPS Cinematic Sweep)
                InkWell(
                  onTap: _toggleAutoSweep,
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _isAutoSweeping
                            ? [const Color(0xFFE11D48), const Color(0xFFBE123C)]
                            : [const Color(0xFF0284C7), const Color(0xFF0369A1)],
                      ),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: _isAutoSweeping
                          ? [
                              BoxShadow(
                                color: const Color(0xFFE11D48).withValues(alpha: 0.4),
                                blurRadius: 6,
                                offset: const Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isAutoSweeping ? Icons.pause : Icons.play_arrow,
                          size: 12,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _isAutoSweeping ? 'Pause Sweep' : 'Auto Sweep',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Transition Percentage Pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.4), width: 0.8),
                  ),
                  child: Text(
                    '${(_transitionProgress * 100).toInt()}% 2D  ⬌  ${(100 - _transitionProgress * 100).toInt()}% 3D',
                    style: const TextStyle(
                      color: Color(0xFF00E5FF),
                      fontSize: 9.0,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            )
          else if (_viewportMode == DdsViewportMode.kinematicFold)
            Row(
              children: [
                // Preset Angle Buttons
                _buildFoldPresetButton(0.0, '0° Flat'),
                const SizedBox(width: 4),
                _buildFoldPresetButton(0.5, '45° Half'),
                const SizedBox(width: 4),
                _buildFoldPresetButton(1.0, '90° Folded'),
                const SizedBox(width: 8),

                // Animate Fold Button
                InkWell(
                  onTap: _toggleAutoFold,
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _isAutoFolding
                            ? [const Color(0xFFE11D48), const Color(0xFFBE123C)]
                            : [const Color(0xFF10B981), const Color(0xFF059669)],
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isAutoFolding ? Icons.pause : Icons.play_arrow,
                          size: 12,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _isAutoFolding ? 'Pause Fold' : 'Animate Fold',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            )
          else
            const Row(
              children: [
                Icon(Icons.sync_alt, size: 12, color: Color(0xFF38BDF8)),
                SizedBox(width: 4),
                Text(
                  'Synchronized Dual Viewports',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 9.0, fontWeight: FontWeight.w600),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildModeTab({
    required DdsViewportMode mode,
    required IconData icon,
    required String label,
    String? badgeText,
  }) {
    final isSelected = _viewportMode == mode;
    return InkWell(
      onTap: () {
        if (_isAutoSweeping) {
          _isAutoSweeping = false;
          _sweepController.stop();
        }
        if (_isAutoFolding) {
          _isAutoFolding = false;
          _foldController.stop();
        }
        setState(() => _viewportMode = mode);
      },
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF334155).withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? const Color(0xFF38BDF8) : Colors.transparent,
            width: 0.8,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 11,
              color: isSelected ? Colors.white : const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
                fontSize: 9.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (badgeText != null) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF0284C7),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    color: isSelected ? const Color(0xFF00E5FF) : Colors.white,
                    fontSize: 7.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFoldPresetButton(double val, String label) {
    final isSelected = (_foldProgress - val).abs() < 0.05;
    return InkWell(
      onTap: () {
        if (_isAutoFolding) {
          _isAutoFolding = false;
          _foldController.stop();
        }
        setState(() => _foldProgress = val);
      },
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF334155),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? const Color(0xFF38BDF8) : Colors.transparent,
            width: 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
            fontSize: 9.0,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildActiveViewport(EvaluatedDdsInstance? eval) {
    switch (_viewportMode) {
      case DdsViewportMode.transitionWipe:
        return _buildTransitionViewport(eval);
      case DdsViewportMode.kinematicFold:
        return _buildKinematicFoldViewport(eval);
      case DdsViewportMode.split:
        return _buildClassicSplitViewport(eval);
    }
  }

  Widget _buildTransitionViewport(EvaluatedDdsInstance? eval) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) {
            if (_isAutoSweeping) {
              setState(() {
                _isAutoSweeping = false;
                _sweepController.stop();
              });
            }
          },
          onHorizontalDragUpdate: (details) {
            if (constraints.maxWidth > 0) {
              setState(() {
                _transitionProgress = (_transitionProgress + details.delta.dx / constraints.maxWidth).clamp(0.0, 1.0);
              });
            }
          },
          onTapDown: (details) {
            if (constraints.maxWidth > 0) {
              setState(() {
                if (_isAutoSweeping) {
                  _isAutoSweeping = false;
                  _sweepController.stop();
                }
                _transitionProgress = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
              });
            }
          },
          child: Stack(
            children: [
              // Combined 2D to 3D Shader/Clipped Painter
              Positioned.fill(
                child: CustomPaint(
                  painter: Dds2Dto3DTransitionPainter(
                    document: eval?.scaledBaseDocument,
                    mesh: eval?.combinedMesh3D,
                    transitionProgress: _transitionProgress,
                    showCrossHatching: _showHatching,
                    showDividerLine: true,
                    dividerColor: const Color(0xFF00E5FF),
                  ),
                ),
              ),

              // Bottom instruction pill overlay
              Positioned(
                bottom: 8,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3), width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.swipe, size: 12, color: Color(0xFF00E5FF)),
                        const SizedBox(width: 6),
                        Text(
                          'Drag cyan laser divider left/right or click anywhere to transition between 2D Blueprint & 3D Shaded Solid',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 8.5,
                            fontWeight: FontWeight.w500,
                          ),
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
    );
  }

  Widget _buildKinematicFoldViewport(EvaluatedDdsInstance? eval) {
    final doc = eval?.scaledBaseDocument;
    FoldedMeshResult? dynamicMesh;
    if (doc != null) {
      if ((_foldProgress - 1.0).abs() < 0.001) {
        dynamicMesh = eval?.combinedMesh3D;
      } else {
        dynamicMesh = KinematicFoldEngine.foldDocument(doc, foldProgress: _foldProgress);
      }
    }

    return Container(
      color: const Color(0xFF0F172A),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: Dds3DIsometricPainter(
                mesh: dynamicMesh,
                backgroundColor: const Color(0xFF0F172A),
              ),
            ),
          ),
          Positioned(
            top: 10,
            left: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'KINEMATIC 3D FLANGE FOLDING SIMULATION',
                  style: TextStyle(color: Color(0xFF38BDF8), fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
                const SizedBox(height: 2),
                Text(
                  'Current Bend Angle: ${(_foldProgress * 90.0).toStringAsFixed(1)}° (${_foldProgress <= 0.05 ? "Unfolded Flat Pattern" : _foldProgress >= 0.95 ? "Fully Formed 90° Channel" : "Progressive Press-Brake Forming"})',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 8.5),
                ),
              ],
            ),
          ),
          // Interactive bottom fold scrubber
          Positioned(
            bottom: 12,
            left: 24,
            right: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Text('0° (Flat)', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 9, fontWeight: FontWeight.bold)),
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        activeTrackColor: const Color(0xFF38BDF8),
                        inactiveTrackColor: const Color(0xFF334155),
                        thumbColor: const Color(0xFF00E5FF),
                        overlayColor: const Color(0xFF00E5FF).withValues(alpha: 0.2),
                        trackHeight: 3.0,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      ),
                      child: Slider(
                        value: _foldProgress,
                        min: 0.0,
                        max: 1.0,
                        onChanged: (val) {
                          if (_isAutoFolding) {
                            setState(() {
                              _isAutoFolding = false;
                              _foldController.stop();
                              _foldProgress = val;
                            });
                          } else {
                            setState(() => _foldProgress = val);
                          }
                        },
                      ),
                    ),
                  ),
                  const Text('90° (Formed)', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 9, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClassicSplitViewport(EvaluatedDdsInstance? eval) {
    return Row(
      children: [
        // Left: 2D Dimensioned Flat/Layout View
        Expanded(
          flex: 5,
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(right: BorderSide(color: Color(0xFF0F172A), width: 1.0)),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: Dds2DDrawingPainter(
                      document: eval?.scaledBaseDocument,
                      coverData: eval?.coverData,
                    ),
                  ),
                ),
                const Positioned(
                  top: 8,
                  left: 8,
                  child: Text(
                    '2D FLAT PATTERN & BEND SPECIFICATION',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 8.5, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Right: 3D Isometric View (Base + Parametric Cover)
        Expanded(
          flex: 5,
          child: Container(
            color: const Color(0xFF0F172A),
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: Dds3DIsometricPainter(
                      mesh: eval?.combinedMesh3D,
                    ),
                  ),
                ),
                const Positioned(
                  top: 8,
                  left: 8,
                  child: Text(
                    '3D ISOMETRIC VIEW (FOLDED BASE + EXPLODED COVER)',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 8.5, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProductBottomDock(DdsProductInstance? inst, EvaluatedDdsInstance? eval) {
    final proj = widget.document.projectInfo;
    final takeoff = eval?.calculatedTakeoff ?? inst?.calculatedTakeoff;

    return Container(
      height: 70,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFF0F172A), width: 1.2)),
      ),
      child: Row(
        children: [
          // Left: Engineering Parameters Summary Table
          Expanded(
            flex: 6,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      _buildMiniParam('MATERIAL', inst?.material ?? 'Pre-Galvanized DX51D'),
                      const SizedBox(width: 14.0),
                      _buildMiniParam('FINISH', inst?.finish ?? 'Mill Galvanized Z275'),
                      const SizedBox(width: 14.0),
                      _buildMiniParam('THICKNESS', '1.5 mm'),
                    ],
                  ),
                  const SizedBox(height: 6.0),
                  Row(
                    children: [
                      _buildMiniParam('BLANK AREA', takeoff != null ? '${takeoff.blankSurfaceAreaM2} m²' : '—'),
                      const SizedBox(width: 14.0),
                      _buildMiniParam('NET WEIGHT', takeoff != null ? '${takeoff.estimatedNetWeightKg} kg' : '—'),
                      const SizedBox(width: 14.0),
                      _buildMiniParam('COVER', inst?.coverConfiguration.included == true ? 'Included (Live Synced)' : 'None'),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Right: ISO 7200 Title Block
          Container(
            width: 280,
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: Color(0xFF0F172A), width: 1.2)),
            ),
            child: Column(
              children: [
                // Top row: Document Number & Title
                Expanded(
                  child: Container(
                    color: const Color(0xFFF1F5F9),
                    padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${proj.documentNumber} • ${proj.documentTitle}',
                      style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const Divider(height: 1, color: Color(0xFF0F172A)),
                // Middle row: Client / Project
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('CLIENT: ${proj.client.isNotEmpty ? proj.client : "Standard"}', style: const TextStyle(fontSize: 8.0, color: Color(0xFF334155))),
                        Text('REV: ${proj.revision}', style: const TextStyle(fontSize: 8.0, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1, color: Color(0xFF0F172A)),
                // Bottom row: Signatures & Sheet Index
                Expanded(
                  child: Container(
                    color: const Color(0xFF0F172A),
                    padding: const EdgeInsets.symmetric(horizontal: 6.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('PREPARED: ${proj.preparedBy.isNotEmpty ? proj.preparedBy : "TruFold"}', style: const TextStyle(fontSize: 8.0, color: Colors.white)),
                        Text('SHEET ${widget.sheet.sheetNumber} OF ${widget.document.totalSheets}', style: const TextStyle(fontSize: 8.0, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8))),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 7.5, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
        const SizedBox(height: 1.0),
        Text(value.isNotEmpty ? value : '—', style: const TextStyle(fontSize: 9.0, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
      ],
    );
  }

  Widget _buildMiniParam(String label, String value) {
    return Row(
      children: [
        Text('$label: ', style: const TextStyle(color: Color(0xFF64748B), fontSize: 8.5, fontWeight: FontWeight.bold)),
        Text(value, style: const TextStyle(color: Color(0xFF0F172A), fontSize: 8.5, fontWeight: FontWeight.w600)),
      ],
    );
  }

  static const TextStyle _tocHeaderStyle = TextStyle(
    fontSize: 8.5,
    fontWeight: FontWeight.bold,
    color: Color(0xFF475569),
  );

  static const TextStyle _tocRowStyle = TextStyle(
    fontSize: 8.5,
    color: Color(0xFF334155),
  );

  static const TextStyle _tocRowStyleBold = TextStyle(
    fontSize: 8.5,
    fontWeight: FontWeight.w600,
    color: Color(0xFF0F172A),
  );
}

// =============================================================================
// 3. Technical Sheet Annotation Overlay Painter
// =============================================================================

class _DdsAnnotationOverlayPainter extends CustomPainter {
  final List<DdsAnnotation> annotations;
  final String? selectedAnnotationId;
  final Size paperSize;
  final CadPoint2D? pendingStartPoint;
  final CadPoint2D? hoverPoint;
  final List<CadPoint2D> pendingCloudPoints;
  final DdsMarkupTool activeTool;

  _DdsAnnotationOverlayPainter({
    required this.annotations,
    this.selectedAnnotationId,
    required this.paperSize,
    this.pendingStartPoint,
    this.hoverPoint,
    required this.pendingCloudPoints,
    required this.activeTool,
  });

  Offset _toPixel(CadPoint2D mm) {
    return Offset(
      (mm.x / 297.0) * paperSize.width,
      (mm.y / 210.0) * paperSize.height,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw Committed Annotations
    for (final ann in annotations) {
      if (!ann.isVisible) continue;
      final isSelected = ann.id == selectedAnnotationId;

      if (ann is DdsLinearDimensionAnnotation) {
        _paintLinearDimension(canvas, ann, isSelected);
      } else if (ann is DdsLeaderNoteAnnotation) {
        _paintLeaderNote(canvas, ann, isSelected);
      } else if (ann is DdsNoteBoxAnnotation) {
        _paintNoteBox(canvas, ann, isSelected);
      } else if (ann is DdsRevisionCloudAnnotation) {
        _paintRevisionCloud(canvas, ann, isSelected);
      } else if (ann is DdsApprovalStampAnnotation) {
        _paintApprovalStamp(canvas, ann, isSelected);
      }
    }

    // 2. Draw Interactive Rubber-Band Previews
    if (pendingStartPoint != null && hoverPoint != null) {
      final p1 = _toPixel(pendingStartPoint!);
      final p2 = _toPixel(hoverPoint!);

      if (activeTool == DdsMarkupTool.linearDimension) {
        final previewPaint = Paint()
          ..color = const Color(0xFF0284C7)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke;
        canvas.drawLine(p1, p2, previewPaint);
        _drawArrowhead(canvas, p2, p1, const Color(0xFF0284C7));
        _drawArrowhead(canvas, p1, p2, const Color(0xFF0284C7));

        final distMm = (pendingStartPoint! - hoverPoint!).length;
        _drawTextBadge(canvas, (p1 + p2) / 2, '${distMm.toStringAsFixed(1)} mm', isSelected: true);
      } else if (activeTool == DdsMarkupTool.leaderNote) {
        final previewPaint = Paint()
          ..color = const Color(0xFF0284C7)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke;
        canvas.drawLine(p1, p2, previewPaint);
        _drawArrowhead(canvas, p1, p2, const Color(0xFF0284C7)); // Arrow at target
      }
    }

    // Revision Cloud in-progress points
    if (pendingCloudPoints.isNotEmpty) {
      final cloudPaint = Paint()
        ..color = const Color(0xFFEF4444)
        ..strokeWidth = 1.4
        ..style = PaintingStyle.stroke;

      final path = Path();
      final pFirst = _toPixel(pendingCloudPoints.first);
      path.moveTo(pFirst.dx, pFirst.dy);
      for (int i = 1; i < pendingCloudPoints.length; i++) {
        final p = _toPixel(pendingCloudPoints[i]);
        path.lineTo(p.dx, p.dy);
      }
      if (hoverPoint != null) {
        final pHover = _toPixel(hoverPoint!);
        path.lineTo(pHover.dx, pHover.dy);
      }
      canvas.drawPath(path, cloudPaint);
    }
  }

  // --- Dimension Line Drawing ---
  void _paintLinearDimension(Canvas canvas, DdsLinearDimensionAnnotation ann, bool isSelected) {
    final p1 = _toPixel(ann.p1);
    final p2 = _toPixel(ann.p2);
    final d = p2 - p1;
    final len = d.distance;
    if (len < 1.0) return;

    final unit = d / len;
    final normal = Offset(-unit.dy, unit.dx);
    final offsetPx = (ann.offsetDistance / 210.0) * paperSize.height;

    final dimP1 = p1 + normal * offsetPx;
    final dimP2 = p2 + normal * offsetPx;

    final color = isSelected ? const Color(0xFF0284C7) : const Color(0xFF0F172A);
    final stroke = Paint()
      ..color = color
      ..strokeWidth = isSelected ? 1.6 : 1.1
      ..style = PaintingStyle.stroke;

    // Witness lines
    canvas.drawLine(p1, dimP1 + normal * 3, stroke);
    canvas.drawLine(p2, dimP2 + normal * 3, stroke);

    // Dimension line
    canvas.drawLine(dimP1, dimP2, stroke);

    // Arrowheads
    _drawArrowhead(canvas, dimP1, dimP2, color);
    _drawArrowhead(canvas, dimP2, dimP1, color);

    // Centered Text
    final mid = (dimP1 + dimP2) / 2;
    _drawTextBadge(canvas, mid, ann.displayText, isSelected: isSelected);
  }

  // --- Leader Note Drawing ---
  void _paintLeaderNote(Canvas canvas, DdsLeaderNoteAnnotation ann, bool isSelected) {
    final target = _toPixel(ann.targetPoint);
    final textPos = _toPixel(ann.textPosition);

    final color = isSelected ? const Color(0xFF0284C7) : const Color(0xFF0F172A);
    final leaderPaint = Paint()
      ..color = color
      ..strokeWidth = isSelected ? 1.6 : 1.1
      ..style = PaintingStyle.stroke;

    // Arrowhead at target pointing towards target
    _drawArrowhead(canvas, target, textPos, color);

    // Angled line
    canvas.drawLine(target, textPos, leaderPaint);

    // Horizontal shoulder line
    final shoulderDx = textPos.dx >= target.dx ? 24.0 : -24.0;
    final shoulderEnd = textPos + Offset(shoulderDx, 0);
    canvas.drawLine(textPos, shoulderEnd, leaderPaint);

    // Note Text above shoulder
    final tp = TextPainter(
      text: TextSpan(
        text: ann.text,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final textOffset = Offset(
      textPos.dx >= target.dx ? textPos.dx + 2 : textPos.dx - tp.width - 2,
      textPos.dy - tp.height - 2,
    );
    tp.paint(canvas, textOffset);
  }

  // --- Note Box Drawing ---
  void _paintNoteBox(Canvas canvas, DdsNoteBoxAnnotation ann, bool isSelected) {
    final rect = Rect.fromLTWH(
      (ann.x / 297.0) * paperSize.width,
      (ann.y / 210.0) * paperSize.height,
      (ann.width / 297.0) * paperSize.width,
      (ann.height / 210.0) * paperSize.height,
    );

    final bgPaint = Paint()..color = const Color(0xFFFFFBEB).withValues(alpha: 0.95);
    final borderPaint = Paint()
      ..color = isSelected ? const Color(0xFF0284C7) : const Color(0xFFD97706)
      ..strokeWidth = isSelected ? 1.8 : 1.0
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4.0));
    canvas.drawRRect(rrect, bgPaint);
    canvas.drawRRect(rrect, borderPaint);

    // Text inside box
    final tp = TextPainter(
      text: TextSpan(
        text: ann.text,
        style: const TextStyle(color: Color(0xFF78350F), fontSize: 8.5, fontWeight: FontWeight.w500),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 4,
    )..layout(maxWidth: rect.width - 8.0);

    tp.paint(canvas, rect.topLeft + const Offset(4.0, 4.0));
  }

  // --- Revision Cloud Drawing ---
  void _paintRevisionCloud(Canvas canvas, DdsRevisionCloudAnnotation ann, bool isSelected) {
    if (ann.points.length < 2) return;

    final color = isSelected ? const Color(0xFF0284C7) : const Color(0xFFDC2626);
    final cloudPaint = Paint()
      ..color = color
      ..strokeWidth = isSelected ? 1.8 : 1.2
      ..style = PaintingStyle.stroke;

    final pts = ann.points.map(_toPixel).toList();
    pts.add(pts.first); // Close loop

    final path = Path();
    path.moveTo(pts.first.dx, pts.first.dy);

    for (int i = 0; i < pts.length - 1; i++) {
      final pA = pts[i];
      final pB = pts[i + 1];
      final dist = (pB - pA).distance;
      const arcStep = 14.0;
      final steps = math.max(1, (dist / arcStep).round());

      for (int s = 0; s < steps; s++) {
        final start = pA + (pB - pA) * (s / steps);
        final end = pA + (pB - pA) * ((s + 1) / steps);
        final segMid = (start + end) / 2;
        final segVec = end - start;
        final segNormal = Offset(-segVec.dy, segVec.dx) / segVec.distance;
        final control = segMid + segNormal * 4.5;
        path.quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
      }
    }

    canvas.drawPath(path, cloudPaint);

    // Draw Δ tag triangle badge
    final tagPos = pts.first + const Offset(-14, -14);
    _drawRevisionDeltaTag(canvas, tagPos, ann.revisionTag, color);
  }

  void _drawRevisionDeltaTag(Canvas canvas, Offset pos, String tag, Color color) {
    final path = Path()
      ..moveTo(pos.dx, pos.dy - 8)
      ..lineTo(pos.dx + 8, pos.dy + 6)
      ..lineTo(pos.dx - 8, pos.dy + 6)
      ..close();

    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1.0);
    canvas.drawPath(path, Paint()..color = Colors.white..style = PaintingStyle.fill);

    final tp = TextPainter(
      text: TextSpan(
        text: tag,
        style: TextStyle(color: color, fontSize: 7.0, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy - tp.height / 2 + 1));
  }

  // --- Approval Stamp Drawing ---
  void _paintApprovalStamp(Canvas canvas, DdsApprovalStampAnnotation ann, bool isSelected) {
    final rect = Rect.fromLTWH(
      (ann.x / 297.0) * paperSize.width,
      (ann.y / 210.0) * paperSize.height,
      (ann.width / 297.0) * paperSize.width,
      (ann.height / 210.0) * paperSize.height,
    );

    final color = const Color(0xFF059669); // Emerald 600
    final borderPaint = Paint()
      ..color = isSelected ? const Color(0xFF0284C7) : color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(3.0));
    canvas.drawRRect(rrect, Paint()..color = const Color(0xFFECFDF5).withValues(alpha: 0.95));
    canvas.drawRRect(rrect, borderPaint);

    final tp = TextPainter(
      text: TextSpan(
        children: [
          const TextSpan(text: 'CLIENT REVIEW STATUS\n', style: TextStyle(color: Color(0xFF065F46), fontSize: 7.5, fontWeight: FontWeight.bold)),
          TextSpan(text: '${ann.status.toUpperCase()}\n', style: const TextStyle(color: Color(0xFF047857), fontSize: 9.5, fontWeight: FontWeight.bold)),
          TextSpan(text: 'By: ${ann.reviewedBy}  •  ${ann.reviewDate}', style: const TextStyle(color: Color(0xFF065F46), fontSize: 7.0)),
        ],
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: rect.width - 4.0);

    tp.paint(canvas, rect.topLeft + Offset((rect.width - tp.width) / 2, (rect.height - tp.height) / 2));
  }

  // --- Shared Arrowhead Helper ---
  void _drawArrowhead(Canvas canvas, Offset tip, Offset from, Color color) {
    final dir = from - tip;
    final len = dir.distance;
    if (len < 0.1) return;
    final unit = dir / len;
    final normal = Offset(-unit.dy, unit.dx);

    const arrowLen = 7.0;
    const arrowWidth = 3.5;

    final p1 = tip + unit * arrowLen + normal * arrowWidth;
    final p2 = tip + unit * arrowLen - normal * arrowWidth;

    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..close();

    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.fill);
  }

  // --- Text Badge Helper ---
  void _drawTextBadge(Canvas canvas, Offset center, String text, {required bool isSelected}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF0F172A),
          fontSize: 8.5,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final bgRect = Rect.fromCenter(
      center: center,
      width: tp.width + 6.0,
      height: tp.height + 4.0,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(2.0)),
      Paint()..color = Colors.white,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(2.0)),
      Paint()
        ..color = isSelected ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );

    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _DdsAnnotationOverlayPainter oldDelegate) => true;
}
