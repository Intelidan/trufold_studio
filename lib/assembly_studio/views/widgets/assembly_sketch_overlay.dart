import 'package:flutter/material.dart';
import '../../../sheet_metal_studio/models/cad_primitives.dart';
import '../../models/assembly_part.dart';
import '../../viewmodels/assembly_studio_viewmodel.dart';
import '../theme/assembly_studio_theme.dart';

/// Full-screen 2D interactive sketch overlay that renders when in Sketch Mode.
/// Focuses on the sheet metal face in front view, allowing direct drawing of holes, obround slots, cuts, and bend lines.
/// Every change immediately updates the 3D folded model (WYSIWYG).
class AssemblySketchOverlay extends StatefulWidget {
  final AssemblyStudioViewModel viewModel;

  const AssemblySketchOverlay({
    super.key,
    required this.viewModel,
  });

  @override
  State<AssemblySketchOverlay> createState() => _AssemblySketchOverlayState();
}

class _AssemblySketchOverlayState extends State<AssemblySketchOverlay> {
  String _selectedTool = 'circle_hole'; // 'circle_hole', 'obround_slot', 'rect_cut', 'bend_line'
  double _holeDiameterMm = 10.0;
  final double _slotLengthMm = 25.0;
  final double _slotWidthMm = 14.0;
  final double _cutWidthMm = 20.0;
  final double _cutHeightMm = 15.0;

  Offset _canvasPan = Offset.zero;
  double _canvasZoom = 1.0;

  AssemblyStudioTheme get theme => AssemblyStudioTheme(isLight: widget.viewModel.isLightBackground);

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final part = vm.doc.parts.where((p) => p.id == vm.sketchPartId).firstOrNull ?? vm.selectedPart;

    if (part == null) {
      return Container();
    }

    final faceLength = part.length;
    final faceHeight = part.height;

    return Container(
      color: const Color(0xEEF8FAFC), // Clean light backdrop
      child: Stack(
        children: [
          // 1. Interactive 2D Drawing Canvas
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleUpdate: (details) {
              if (details.pointerCount > 1) {
                setState(() {
                  _canvasPan += details.focalPointDelta;
                  _canvasZoom = (_canvasZoom * details.scale).clamp(0.4, 4.0);
                });
              }
            },
            onTapUp: (details) {
              _handleCanvasTap(details.localPosition, faceLength, faceHeight, part);
            },
            child: CustomPaint(
              size: Size.infinite,
              painter: _FaceSketchCanvasPainter(
                part: part,
                faceLength: faceLength,
                faceHeight: faceHeight,
                pan: _canvasPan,
                zoom: _canvasZoom,
                selectedTool: _selectedTool,
              ),
            ),
          ),

          // 2. Top Sketch Toolbar
          Positioned(
            top: 16,
            left: 20,
            right: 20,
            child: _buildTopSketchToolbar(context, vm, part),
          ),

          // 3. Left Tool Palette (Hole, Slot, Cut, Bend)
          Positioned(
            top: 80,
            left: 20,
            child: _buildLeftToolsPalette(),
          ),

          // 4. Right Features List & WYSIWYG Live Sync Indicator
          Positioned(
            top: 80,
            right: 20,
            bottom: 20,
            child: _buildRightFeaturesList(vm, part),
          ),

          // 5. Bottom Instructions Pill
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.panelBackground,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: theme.accentSky, width: 1.0),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: theme.isLight ? 0.08 : 0.4), blurRadius: 8, offset: const Offset(0, 2)),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.touch_app_rounded, size: 14, color: theme.accentSky),
                    const SizedBox(width: 8),
                    Text(
                      'Click on the sheet metal face to place $_selectedToolLabel • Updates 3D model in real time (WYSIWYG)',
                      style: TextStyle(fontSize: 11, color: theme.textPrimary, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _selectedToolLabel {
    switch (_selectedTool) {
      case 'circle_hole':
        return 'Ø${_holeDiameterMm.toInt()}mm Hole';
      case 'obround_slot':
        return '${_slotLengthMm.toInt()}x${_slotWidthMm.toInt()}mm Obround Slot';
      case 'rect_cut':
        return '${_cutWidthMm.toInt()}x${_cutHeightMm.toInt()}mm Cutout';
      case 'bend_line':
        return 'Bend Line';
      default:
        return 'Feature';
    }
  }

  void _handleCanvasTap(Offset tapPos, double faceLength, double faceHeight, AssemblyPart part) {
    final mediaSize = MediaQuery.of(context).size;
    final cx = mediaSize.width / 2.0 + _canvasPan.dx;
    final cy = mediaSize.height / 2.0 + _canvasPan.dy;

    const basePpm = 0.8; // Pixels per mm
    final ppm = basePpm * _canvasZoom;

    // Sheet origin on screen
    final ox = cx - (faceLength * ppm) / 2.0;
    final oy = cy + (faceHeight * ppm) / 2.0;

    // Convert tapPos to sheet mm coordinates
    final mmX = (tapPos.dx - ox) / ppm;
    final mmY = (oy - tapPos.dy) / ppm; // Invert Y so 0 is bottom, H is top

    // Check if within bounds or near bounds
    if (mmX >= -10.0 && mmX <= faceLength + 10.0 && mmY >= -10.0 && mmY <= faceHeight + 10.0) {
      final clampedX = mmX.clamp(0.0, faceLength);
      final clampedY = mmY.clamp(0.0, faceHeight);

      double w = 10.0;
      double h = 10.0;
      if (_selectedTool == 'circle_hole') {
        w = _holeDiameterMm;
        h = _holeDiameterMm;
      } else if (_selectedTool == 'obround_slot') {
        w = _slotLengthMm;
        h = _slotWidthMm;
      } else if (_selectedTool == 'rect_cut') {
        w = _cutWidthMm;
        h = _cutHeightMm;
      } else if (_selectedTool == 'bend_line') {
        w = 2.0;
        h = faceHeight;
      }

      widget.viewModel.addSketchFeature(
        featureType: _selectedTool,
        localCenter: CadPoint2D(clampedX, clampedY),
        widthMm: w,
        heightMm: h,
      );
    }
  }

  Widget _buildTopSketchToolbar(BuildContext context, AssemblyStudioViewModel vm, AssemblyPart part) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: theme.panelBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.panelBorder, width: 1.0),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: theme.isLight ? 0.08 : 0.4), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.draw_rounded, color: theme.accentSky, size: 20),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SKETCHING ON: ${part.name.toUpperCase()}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: theme.textPrimary),
              ),
              Text(
                'Face: ${vm.sketchFaceId ?? "Web"} • Bounds: ${part.length.toInt()} × ${part.height.toInt()} mm',
                style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
              ),
            ],
          ),
          const Spacer(),

          // Live WYSIWYG badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF10B981)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.sync_rounded, size: 12, color: Color(0xFF34D399)),
                SizedBox(width: 4),
                Text('WYSIWYG Live Sync Active', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF34D399))),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Done & Fold Button
          ElevatedButton.icon(
            icon: const Icon(Icons.check_circle_rounded, size: 16),
            label: const Text('Done & Fold 3D', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: vm.exitSketchMode,
          ),
        ],
      ),
    );
  }

  Widget _buildLeftToolsPalette() {
    return Container(
      width: 190,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.panelBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.panelBorder, width: 1.0),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: theme.isLight ? 0.08 : 0.4), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'SKETCH TOOLS',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: theme.textTertiary),
          ),
          const SizedBox(height: 10),

          // 1. Hole Tool
          _buildToolCard(
            id: 'circle_hole',
            icon: Icons.radio_button_unchecked_rounded,
            label: 'Hole (Ø10mm)',
            subtitle: 'Splice / coupler bolt hole',
          ),
          if (_selectedTool == 'circle_hole') ...[
            const SizedBox(height: 6),
            Row(
              children: [10.0, 12.0, 14.0].map((d) {
                final isSel = (_holeDiameterMm - d).abs() < 0.1;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2.0),
                    child: InkWell(
                      onTap: () => setState(() => _holeDiameterMm = d),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSel ? const Color(0xFF0284C7) : const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('Ø${d.toInt()}', style: const TextStyle(fontSize: 9, color: Colors.white)),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 8),

          // 2. Obround Slot Tool
          _buildToolCard(
            id: 'obround_slot',
            icon: Icons.crop_portrait_rounded,
            label: 'Obround Slot',
            subtitle: '25x14mm Cable tie slot',
          ),

          const SizedBox(height: 8),

          // 3. Rect Cutout Tool
          _buildToolCard(
            id: 'rect_cut',
            icon: Icons.crop_square_rounded,
            label: 'Rect Cutout',
            subtitle: 'Notch or window cutout',
          ),

          const SizedBox(height: 8),

          // 4. Bend Line Tool
          _buildToolCard(
            id: 'bend_line',
            icon: Icons.straighten_rounded,
            label: 'Bend Line',
            subtitle: 'Fold / brake press line',
          ),
        ],
      ),
    );
  }

  Widget _buildToolCard({
    required String id,
    required IconData icon,
    required String label,
    required String subtitle,
  }) {
    final isSelected = _selectedTool == id;
    return InkWell(
      onTap: () => setState(() => _selectedTool = id),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected ? theme.accentSkyBg : theme.cardBackground,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? theme.accentSky : theme.cardBorder,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF64748B)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? const Color(0xFF0369A1) : const Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 8, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRightFeaturesList(AssemblyStudioViewModel vm, AssemblyPart part) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.panelBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.panelBorder, width: 1.0),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: theme.isLight ? 0.08 : 0.4), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'DRAWN FEATURES',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: theme.textTertiary),
              ),
              Text(
                '${part.sketches.length} items',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
              ),
            ],
          ),
          const SizedBox(height: 8),

          Expanded(
            child: part.sketches.isEmpty
                ? const Center(
                    child: Text(
                      'No cuts or holes drawn yet.\nClick on the face to add.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                    ),
                  )
                : ListView.builder(
                    itemCount: part.sketches.length,
                    itemBuilder: (ctx, idx) {
                      final sk = part.sketches[idx];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              sk.featureType == 'circle_hole'
                                  ? Icons.radio_button_unchecked_rounded
                                  : Icons.crop_portrait_rounded,
                              size: 14,
                              color: const Color(0xFF38BDF8),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    sk.featureType.replaceAll('_', ' ').toUpperCase(),
                                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                                  ),
                                  Text(
                                    'X:${sk.localCenter.x.toInt()}mm • Y:${sk.localCenter.y.toInt()}mm',
                                    style: const TextStyle(fontSize: 8, color: Color(0xFF94A3B8)),
                                  ),
                                ],
                              ),
                            ),
                            InkWell(
                              onTap: () => vm.removeSketchFeature(part.id, sk.id),
                              child: const Icon(Icons.close_rounded, size: 14, color: Color(0xFFEF4444)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// CustomPainter that renders the sheet metal face boundary, millimeter grid rulers, and sketched features in 2D.
class _FaceSketchCanvasPainter extends CustomPainter {
  final AssemblyPart part;
  final double faceLength;
  final double faceHeight;
  final Offset pan;
  final double zoom;
  final String selectedTool;

  _FaceSketchCanvasPainter({
    required this.part,
    required this.faceLength,
    required this.faceHeight,
    required this.pan,
    required this.zoom,
    required this.selectedTool,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2.0 + pan.dx;
    final cy = size.height / 2.0 + pan.dy;

    const basePpm = 0.8;
    final ppm = basePpm * zoom;

    final rectW = faceLength * ppm;
    final rectH = faceHeight * ppm;

    final ox = cx - rectW / 2.0;
    final oy = cy - rectH / 2.0;

    // 1. Draw CAD Blueprint Grid
    _drawGrid(canvas, size, ox, oy, ppm, rectW, rectH);

    // 2. Draw Sheet Metal Face Outline
    final faceRect = Rect.fromLTWH(ox, oy, rectW, rectH);
    final fillPaint = Paint()..color = const Color(0xFFE2E8F0); // Metallic sheet color
    canvas.drawRect(faceRect, fillPaint);

    final borderPaint = Paint()
      ..color = const Color(0xFF0284C7)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawRect(faceRect, borderPaint);

    // 3. Draw Default Coupler Splice Holes (if straight rail)
    if (part.type == AssemblyPartType.straightRail && faceLength >= 100.0) {
      final z1 = (faceHeight / 2.0) - 12.5;
      final z2 = (faceHeight / 2.0) + 12.5;
      for (final x in [35.0, 75.0, faceLength - 75.0, faceLength - 35.0]) {
        for (final z in [z1, z2]) {
          final sx = ox + x * ppm;
          final sy = oy + (faceHeight - z) * ppm;
          _drawHole(canvas, Offset(sx, sy), 5.0 * ppm, isCouplerHole: true);
        }
      }
    }

    // 4. Draw Sketched Features on Face
    for (final sk in part.sketches) {
      final sx = ox + sk.localCenter.x * ppm;
      final sy = oy + (faceHeight - sk.localCenter.y) * ppm;

      if (sk.featureType == 'circle_hole') {
        _drawHole(canvas, Offset(sx, sy), (sk.widthMm / 2.0) * ppm);
      } else if (sk.featureType == 'obround_slot') {
        _drawObroundSlot(canvas, Offset(sx, sy), sk.widthMm * ppm, sk.heightMm * ppm);
      } else if (sk.featureType == 'rect_cut' || sk.featureType == 'rung_slot' || sk.isRungSlotEntity) {
        _drawRectCut(canvas, Offset(sx, sy), sk.widthMm * ppm, sk.heightMm * ppm);
      } else if (sk.featureType == 'bend_line') {
        _drawBendLine(canvas, sx, oy, faceHeight * ppm);
      }
    }

    // 5. Dimension labels
    _drawDimensionText(canvas, '${faceLength.toInt()} mm', Offset(ox + rectW / 2.0, oy - 16));
    _drawDimensionText(canvas, '${faceHeight.toInt()} mm', Offset(ox - 35, oy + rectH / 2.0), isVertical: true);
  }

  void _drawGrid(Canvas canvas, Size size, double ox, double oy, double ppm, double rectW, double rectH) {
    final gridPaint = Paint()
      ..color = const Color(0xFF1E293B).withValues(alpha: 0.5)
      ..strokeWidth = 1.0;

    const double stepMm = 50.0;
    final stepPx = stepMm * ppm;

    for (double x = ox; x <= ox + rectW; x += stepPx) {
      canvas.drawLine(Offset(x, oy), Offset(x, oy + rectH), gridPaint);
    }
    for (double y = oy; y <= oy + rectH; y += stepPx) {
      canvas.drawLine(Offset(ox, y), Offset(ox + rectW, y), gridPaint);
    }
  }

  void _drawHole(Canvas canvas, Offset center, double radius, {bool isCouplerHole = false}) {
    final holePaint = Paint()
      ..color = isCouplerHole ? const Color(0xFF0F172A) : const Color(0xFFEF4444)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, holePaint);

    final borderPaint = Paint()
      ..color = isCouplerHole ? const Color(0xFF64748B) : Colors.white
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius, borderPaint);

    // Crosshairs
    canvas.drawLine(Offset(center.dx - radius - 2, center.dy), Offset(center.dx + radius + 2, center.dy), borderPaint);
    canvas.drawLine(Offset(center.dx, center.dy - radius - 2), Offset(center.dx, center.dy + radius + 2), borderPaint);
  }

  void _drawObroundSlot(Canvas canvas, Offset center, double lengthPx, double widthPx) {
    final r = widthPx / 2.0;

    final slotPaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = const Color(0xFF10B981)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;

    final rRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: lengthPx, height: widthPx),
      Radius.circular(r),
    );
    canvas.drawRRect(rRect, slotPaint);
    canvas.drawRRect(rRect, strokePaint);
  }

  void _drawRectCut(Canvas canvas, Offset center, double w, double h) {
    final rect = Rect.fromCenter(center: center, width: w, height: h);
    final fillPaint = Paint()..color = const Color(0xFF0F172A);
    final strokePaint = Paint()
      ..color = const Color(0xFFF59E0B)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;
    canvas.drawRect(rect, fillPaint);
    canvas.drawRect(rect, strokePaint);
  }

  void _drawBendLine(Canvas canvas, double sx, double topY, double heightPx) {
    final bendPaint = Paint()
      ..color = const Color(0xFFF59E0B)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    double curY = topY;
    while (curY < topY + heightPx) {
      final endY = (curY + 8.0).clamp(topY, topY + heightPx);
      canvas.drawLine(Offset(sx, curY), Offset(sx, endY), bendPaint);
      curY += 14.0;
    }

    final tp = TextPainter(
      text: const TextSpan(
        text: 'BEND LINE 90°',
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFFD97706)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(sx + 4, topY + heightPx / 2.0);
    canvas.rotate(-1.5708);
    tp.paint(canvas, Offset(-tp.width / 2.0, 0));
    canvas.restore();
  }

  void _drawDimensionText(Canvas canvas, String text, Offset pos, {bool isVertical = false}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8))),
      textDirection: TextDirection.ltr,
    )..layout();

    if (isVertical) {
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(-1.5708);
      tp.paint(canvas, Offset(-tp.width / 2.0, 0));
      canvas.restore();
    } else {
      tp.paint(canvas, Offset(pos.dx - tp.width / 2.0, pos.dy));
    }
  }

  @override
  bool shouldRepaint(covariant _FaceSketchCanvasPainter oldDelegate) {
    return true;
  }
}
