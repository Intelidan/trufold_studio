// =============================================================================
// assembly_dsf_anatomy_dialog.dart
//
// Interactive CAD Anatomy Inspector Window for Sheet Metal .dsf parts in Assembly Studio.
// Displays 2D Flat Pattern blanks, kinematic bend tables, CNC punch coordinates,
// and enables 1-click cross-studio navigation into Sheet Metal Studio.
// =============================================================================

import 'package:flutter/material.dart';

import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/fold_bend_line.dart';
import 'package:trufold_studio/sheet_metal_studio/views/sheet_metal_studio_screen.dart';
import 'package:trufold_studio/assembly_studio/models/assembly_part.dart';
import 'package:trufold_studio/assembly_studio/viewmodels/assembly_studio_viewmodel.dart';

class AssemblyDsfAnatomyDialog extends StatefulWidget {
  final AssemblyPart part;
  final AssemblyStudioViewModel viewModel;

  const AssemblyDsfAnatomyDialog({
    super.key,
    required this.part,
    required this.viewModel,
  });

  static void show(BuildContext context, AssemblyPart part, AssemblyStudioViewModel vm) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => AssemblyDsfAnatomyDialog(part: part, viewModel: vm),
    );
  }

  @override
  State<AssemblyDsfAnatomyDialog> createState() => _AssemblyDsfAnatomyDialogState();
}

class _AssemblyDsfAnatomyDialogState extends State<AssemblyDsfAnatomyDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DsfDocument? _dsfDoc;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _dsfDoc = widget.part.getEffectiveDsfDocument();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dsf = _dsfDoc;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 840,
        height: 640,
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF334155), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.55),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            _buildHeader(context),

            // Tab Bar
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFF1E293B),
                border: Border(bottom: BorderSide(color: Color(0xFF334155))),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorColor: const Color(0xFF0284C7),
                indicatorWeight: 3,
                labelColor: Colors.white,
                unselectedLabelColor: const Color(0xFF94A3B8),
                labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                tabs: const [
                  Tab(icon: Icon(Icons.crop_landscape_rounded, size: 16), text: '2D Flat Blank'),
                  Tab(icon: Icon(Icons.turn_right_rounded, size: 16), text: 'Bend Table'),
                  Tab(icon: Icon(Icons.grain_rounded, size: 16), text: 'CNC Punches'),
                  Tab(icon: Icon(Icons.info_outline_rounded, size: 16), text: 'Part Specs'),
                ],
              ),
            ),

            // Body
            Expanded(
              child: dsf == null
                  ? _buildNoDsfNotice()
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildFlatPatternTab(dsf),
                        _buildBendTableTab(dsf),
                        _buildPunchesTab(dsf),
                        _buildSpecsTab(dsf),
                      ],
                    ),
            ),

            // Footer / Cross-Studio Action
            _buildFooter(context, dsf),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
        border: Border(bottom: BorderSide(color: Color(0xFF334155))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: const Color(0xFF0284C7).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.4)),
            ),
            child: const Icon(Icons.architecture_rounded, color: Color(0xFF38BDF8), size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.part.name,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'DSF CAD Anatomy • Type: ${widget.part.type.name} • ID: ${widget.part.id}',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 20),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _buildNoDsfNotice() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.layers_clear_outlined, size: 48, color: Color(0xFF64748B)),
          const SizedBox(height: 12),
          const Text(
            'No Native .dsf Sheet Metal Geometry Attached',
            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              'This part was generated as a pure 3D extrusion/solid primitive. Import a .dsf file or Cable Management template to view complete bend tables, flat blanks, and CNC punch schedules.',
              textAlign: TextAlign.center,
              style: TextStyle(color: const Color(0xFF94A3B8), fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlatPatternTab(DsfDocument dsf) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildBadge('Contour Vertices', '${dsf.outerContour.length} pts', const Color(0xFF0284C7)),
              const SizedBox(width: 10),
              _buildBadge('Press Bends', '${dsf.bends.length} lines', const Color(0xFF10B981)),
              const SizedBox(width: 10),
              _buildBadge('CNC Punches', '${dsf.allPunches.length} holes', const Color(0xFFF59E0B)),
              const Spacer(),
              Text(
                'Material: ${dsf.material.materialGrade} (${dsf.material.thicknessMm}mm)',
                style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11.5),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF0B132B),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF1E293B)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CustomPaint(
                  painter: _DsfFlatPatternPreviewPainter(dsf: dsf),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBendTableTab(DsfDocument dsf) {
    if (dsf.bends.isEmpty) {
      return const Center(
        child: Text('No bends found in this part (Flat Plate)', style: TextStyle(color: Color(0xFF94A3B8))),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: dsf.bends.length,
      separatorBuilder: (context, index) => const Divider(color: Color(0xFF334155), height: 1),
      itemBuilder: (context, idx) {
        final b = dsf.bends[idx];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF10B981)),
                ),
                child: Text('${idx + 1}', style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b.id, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      'P1: (${b.p1.x.toStringAsFixed(1)}, ${b.p1.y.toStringAsFixed(1)}) → P2: (${b.p2.x.toStringAsFixed(1)}, ${b.p2.y.toStringAsFixed(1)})',
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${b.targetAngleDeg.abs().toStringAsFixed(1)}° ${b.direction == BendDirection.up ? "UP" : "DOWN"}',
                    style: TextStyle(
                      color: b.direction == BendDirection.up ? const Color(0xFF38BDF8) : const Color(0xFFF59E0B),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Radius: ${b.radiusMm.toStringAsFixed(1)}mm • Deduct: ${(b.deductionOverride ?? 0.0).toStringAsFixed(2)}mm',
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 10.5),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPunchesTab(DsfDocument dsf) {
    final punches = dsf.allPunches;
    if (punches.isEmpty) {
      return const Center(
        child: Text('No CNC punches or holes on this part', style: TextStyle(color: Color(0xFF94A3B8))),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: punches.length,
      separatorBuilder: (context, index) => const Divider(color: Color(0xFF334155), height: 1),
      itemBuilder: (context, idx) {
        final p = punches[idx];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.radio_button_checked_rounded, color: Color(0xFFF59E0B), size: 16),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  p.id,
                  style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                'Pos: (${p.center.x.toStringAsFixed(1)}, ${p.center.y.toStringAsFixed(1)})',
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
              ),
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Ø${p.diameterMm.toStringAsFixed(1)} mm',
                  style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSpecsTab(DsfDocument dsf) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSpecRow('Product System', dsf.productType),
          _buildSpecRow('Item Name', dsf.itemName),
          _buildSpecRow('Material Grade', dsf.material.materialGrade),
          _buildSpecRow('Thickness', '${dsf.material.thicknessMm} mm'),
          _buildSpecRow('Paint / Finish', dsf.material.paintCoat.displayLabel),
          _buildSpecRow('K-Factor', dsf.material.kFactor.toStringAsFixed(3)),
          _buildSpecRow('Outer Contour Segments', '${dsf.outerContour.length} vertices'),
          _buildSpecRow('B-Rep Planar Faces', '${dsf.faces.length} faces'),
          _buildSpecRow('Bends Count', '${dsf.bends.length} lines'),
          _buildSpecRow('CNC Punches Count', '${dsf.allPunches.length} holes'),
        ],
      ),
    );
  }

  Widget _buildSpecRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 180,
            child: Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String label, String val, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text('$label: $val', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildFooter(BuildContext context, DsfDocument? dsf) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12)),
        border: Border(top: BorderSide(color: Color(0xFF334155))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            dsf != null ? 'Format: ${dsf.format} v${dsf.version}' : 'Non-DSF Solid Body',
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
          ),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.check_rounded, size: 16),
                label: const Text('Done'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF475569)),
                ),
              ),
              const SizedBox(width: 10),
              if (dsf != null)
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    // Cross-Studio Navigation: Open this exact DSF part in Sheet Metal Studio!
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SheetMetalStudioScreen(
                          initialDocument: dsf,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('Edit in Sheet Metal Studio'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DsfFlatPatternPreviewPainter extends CustomPainter {
  final DsfDocument dsf;

  _DsfFlatPatternPreviewPainter({required this.dsf});

  @override
  void paint(Canvas canvas, Size size) {
    if (dsf.outerContour.isEmpty) return;

    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;

    for (final p in dsf.outerContour) {
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }

    final spanW = maxX - minX;
    final spanH = maxY - minY;
    if (spanW <= 0 || spanH <= 0) return;

    const pad = 24.0;
    final availW = size.width - pad * 2;
    final availH = size.height - pad * 2;
    final scale = (availW / spanW < availH / spanH ? availW / spanW : availH / spanH).clamp(0.01, 10.0);

    final midX = (minX + maxX) / 2.0;
    final midY = (minY + maxY) / 2.0;

    Offset toScreen(double x, double y) {
      return Offset(
        size.width / 2.0 + (x - midX) * scale,
        size.height / 2.0 - (y - midY) * scale,
      );
    }

    // 1. Draw Outer Cutting Contour
    final contourPaint = Paint()
      ..color = const Color(0xFF38BDF8)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = const Color(0xFF0284C7).withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;

    final path = Path();
    for (int i = 0; i < dsf.outerContour.length; i++) {
      final pt = toScreen(dsf.outerContour[i].x, dsf.outerContour[i].y);
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, contourPaint);

    // 2. Draw Bend Lines
    final bendPaint = Paint()
      ..color = const Color(0xFF10B981)
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke;

    for (final b in dsf.bends) {
      final p1 = toScreen(b.p1.x, b.p1.y);
      final p2 = toScreen(b.p2.x, b.p2.y);
      canvas.drawLine(p1, p2, bendPaint);
    }

    // 3. Draw CNC Punches
    final punchPaint = Paint()
      ..color = const Color(0xFFF59E0B)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    for (final punch in dsf.allPunches) {
      final cp = toScreen(punch.center.x, punch.center.y);
      final r = (punch.diameterMm / 2.0) * scale;
      canvas.drawCircle(cp, r.clamp(2.0, 40.0), punchPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _DsfFlatPatternPreviewPainter oldDelegate) => true;
}
