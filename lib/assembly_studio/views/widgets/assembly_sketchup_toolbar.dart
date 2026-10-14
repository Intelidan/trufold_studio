import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../viewmodels/assembly_studio_viewmodel.dart';

/// Authentic SketchUp-style vertical tool palette matching Screenshot SS2.
/// Features Select, Materials, Pencil, Rectangle, Circle, Arc, Freehand,
/// Move, Rotate, Scale, Tape Measure/Dimension, Protractor, Zoom, and Zoom Extents.
class AssemblySketchupToolbar extends StatelessWidget {
  final AssemblyStudioViewModel viewModel;
  final VoidCallback onZoomExtents;
  final VoidCallback? onOpenMaterials;
  final VoidCallback? onOpenDimensionMode;

  const AssemblySketchupToolbar({
    super.key,
    required this.viewModel,
    required this.onZoomExtents,
    this.onOpenMaterials,
    this.onOpenDimensionMode,
  });

  @override
  Widget build(BuildContext context) {
    final activeTool = viewModel.activeToolMode;
    final isSketch = viewModel.isSketchMode;
    final sketchTool = viewModel.activeSketchTool;
    final isLight = viewModel.isLightBackground;

    return Container(
      width: 42,
      decoration: BoxDecoration(
        color: isLight ? Colors.white.withValues(alpha: 0.96) : const Color(0xFF1E1E26).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isLight ? const Color(0xFFCBD5E1) : const Color(0xFF32323E), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isLight ? 0.12 : 0.45),
            blurRadius: 10,
            offset: const Offset(2, 4),
          ),
        ],
      ),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
          // Top grip dots
          _buildGripDots(isLight: isLight),
          const SizedBox(height: 2),

          // 1. Select Tool (Cursor + drop indicator)
          _buildToolButton(
            tooltip: 'Select (Space / V)',
            isActive: !isSketch && activeTool == SketchUpToolMode.select,
            iconPainter: const _SelectIconPainter(),
            hasDropdown: true,
            onTap: () {
              if (isSketch) viewModel.finishSketch();
              viewModel.setToolMode(SketchUpToolMode.select);
            },
          ),

          // 2. Materials / Paint Bucket Tool
          _buildToolButton(
            tooltip: 'Materials & Finishes (B)',
            isActive: false,
            iconPainter: const _PaintBucketIconPainter(),
            onTap: () {
              if (onOpenMaterials != null) {
                onOpenMaterials!();
              } else {
                _showMaterialsQuickPicker(context);
              }
            },
          ),

          // 3. Pencil / Line Sketch Tool
          _buildToolButton(
            tooltip: 'Line / Pencil (L)',
            isActive: isSketch && sketchTool == 'line',
            iconPainter: const _PencilIconPainter(),
            onTap: () {
              if (!isSketch) {
                viewModel.focusPartAndEnterSketch(viewModel.selectedPart?.id);
              }
              viewModel.setActiveSketchTool('line');
            },
          ),

          // 4. Rectangle Sketch Tool
          _buildToolButton(
            tooltip: 'Rectangle (Rect Cut)',
            isActive: isSketch && sketchTool == 'rect',
            iconPainter: const _RectangleIconPainter(),
            onTap: () {
              if (!isSketch) {
                viewModel.focusPartAndEnterSketch(viewModel.selectedPart?.id);
              }
              viewModel.setActiveSketchTool('rect');
            },
          ),

          // 5. Circle / Punch Hole Tool
          _buildToolButton(
            tooltip: 'Circle / Hole (C)',
            isActive: isSketch && sketchTool == 'hole',
            iconPainter: const _CircleIconPainter(),
            onTap: () {
              if (!isSketch) {
                viewModel.focusPartAndEnterSketch(viewModel.selectedPart?.id);
              }
              viewModel.setActiveSketchTool('hole');
            },
          ),

          // 6. Arc Tool (2-Point Arc)
          _buildToolButton(
            tooltip: '2-Point Arc (A)',
            isActive: isSketch && sketchTool == 'arc',
            iconPainter: const _ArcIconPainter(),
            onTap: () {
              if (!isSketch) {
                viewModel.focusPartAndEnterSketch(viewModel.selectedPart?.id);
              }
              viewModel.setActiveSketchTool('arc');
            },
          ),

          // 7. Freehand / Slot Tool
          _buildToolButton(
            tooltip: 'Punched Rung Slot / Spline',
            isActive: isSketch && sketchTool == 'rung_slot',
            iconPainter: const _SplineSlotIconPainter(),
            onTap: () {
              if (!isSketch) {
                viewModel.focusPartAndEnterSketch(viewModel.selectedPart?.id);
              }
              viewModel.setActiveSketchTool('rung_slot');
            },
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
            child: Divider(color: isLight ? const Color(0xFFE2E8F0) : const Color(0xFF2E2E38), height: 1),
          ),

          // 8. Move Tool (4-way Red Arrows)
          _buildToolButton(
            tooltip: 'Move (M) • Lock axis with arrow keys',
            isActive: !isSketch && activeTool == SketchUpToolMode.move,
            iconPainter: const _MoveIconPainter(),
            onTap: () {
              if (isSketch) viewModel.finishSketch();
              viewModel.setToolMode(SketchUpToolMode.move);
            },
          ),

          // 9. Rotate Tool (Circular Red Arrows / Protractor)
          _buildToolButton(
            tooltip: 'Rotate (R / Q) • 15° Protractor Snap',
            isActive: !isSketch && activeTool == SketchUpToolMode.rotate,
            iconPainter: const _RotateIconPainter(),
            onTap: () {
              if (isSketch) viewModel.finishSketch();
              viewModel.setToolMode(SketchUpToolMode.rotate);
            },
          ),

          // 9b. Auto-Span Face-to-Face Bridge Tool (B)
          _buildToolButton(
            tooltip: 'Auto-Span Bridge (B) • Connect stiles with rungs & welds',
            isActive: !isSketch && activeTool == SketchUpToolMode.bridge,
            iconPainter: const _BridgeIconPainter(),
            onTap: () {
              if (isSketch) viewModel.finishSketch();
              viewModel.setToolMode(SketchUpToolMode.bridge);
            },
          ),

          // 9c. Fillet Weld Tool (W)
          _buildToolButton(
            tooltip: 'Fillet Weld (W) • Drag draft line across seam to weld',
            isActive: !isSketch && activeTool == SketchUpToolMode.weld,
            iconPainter: const _WeldIconPainter(),
            onTap: () {
              if (isSketch) viewModel.finishSketch();
              viewModel.setToolMode(SketchUpToolMode.weld);
            },
          ),

          // 9d. Magnetic Coupling Tool (J)
          _buildToolButton(
            tooltip: 'Magnetic Snap & Joint (J) • Place snap spot & attract parts',
            isActive: !isSketch && activeTool == SketchUpToolMode.magnetic,
            iconPainter: const _MagneticIconPainter(),
            onTap: () {
              if (isSketch) viewModel.finishSketch();
              viewModel.setToolMode(SketchUpToolMode.magnetic);
            },
          ),

          // 10. Scale Tool (Box with Red Diagonal Expand Arrow)
          _buildToolButton(
            tooltip: 'Scale / Dimensions (S)',
            isActive: false,
            iconPainter: const _ScaleIconPainter(),
            onTap: () {
              _showScaleDialog(context);
            },
          ),

          // 11. Tape Measure / Dimension Tool
          _buildToolButton(
            tooltip: 'Tape Measure / Dimension (D)',
            isActive: false,
            iconPainter: const _TapeMeasureIconPainter(),
            onTap: () {
              if (onOpenDimensionMode != null) {
                onOpenDimensionMode!();
              } else {
                _showMeasureInfo(context);
              }
            },
          ),

          // 12. Protractor Tool
          _buildToolButton(
            tooltip: 'Protractor (Angle Guide)',
            isActive: false,
            iconPainter: const _ProtractorIconPainter(),
            onTap: () {
              if (isSketch) viewModel.finishSketch();
              viewModel.setToolMode(SketchUpToolMode.rotate);
            },
          ),

          // 13. Orbit Camera Tool (O) (SS1)
          _buildToolButton(
            tooltip: 'Orbit Camera (O) • Shift + Middle Drag / Right Drag',
            isActive: !isSketch && activeTool == SketchUpToolMode.orbit,
            iconPainter: const OrbitIconPainter(),
            onTap: () {
              if (isSketch) viewModel.finishSketch();
              viewModel.setToolMode(SketchUpToolMode.orbit);
            },
          ),

          // 14. Pan Camera Tool (H) (SS1)
          _buildToolButton(
            tooltip: 'Pan Camera (H) • Middle Mouse Drag',
            isActive: !isSketch && activeTool == SketchUpToolMode.pan,
            iconPainter: const PanIconPainter(),
            onTap: () {
              if (isSketch) viewModel.finishSketch();
              viewModel.setToolMode(SketchUpToolMode.pan);
            },
          ),

          // 15. Zoom / Orbit Tool
          _buildToolButton(
            tooltip: 'Zoom / Orbit Camera (Z)',
            isActive: false,
            iconPainter: const _ZoomIconPainter(),
            onTap: () {
              viewModel.updateZoom(1.25);
            },
          ),

          // 16. Zoom Extents / Fit (Magnifier + 4 Red Outward Arrows)
          _buildToolButton(
            tooltip: 'Zoom to Fit / Extents (F)',
            isActive: false,
            iconPainter: const _ZoomExtentsIconPainter(),
            onTap: onZoomExtents,
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
            child: Divider(color: isLight ? const Color(0xFFE2E8F0) : const Color(0xFF2E2E38), height: 1),
          ),

          // 15. Canvas Background Theme Toggle (Sun / Moon)
          _buildToolButton(
            tooltip: isLight ? 'Switch to Dark Studio Canvas (Alt+T)' : 'Switch to Light Studio Canvas (Alt+T)',
            isActive: isLight,
            iconPainter: _ThemeModeIconPainter(isLight: isLight),
            onTap: () {
              viewModel.toggleBackgroundMode();
            },
          ),

          const SizedBox(height: 2),
          // Bottom grip dots
          _buildGripDots(isLight: isLight),
          const SizedBox(height: 3),
        ],
      ),
      ),
    );
  }

  Widget _buildGripDots({bool isLight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          6,
          (i) => Container(
            width: 2.2,
            height: 2.2,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: isLight ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolButton({
    required String tooltip,
    required bool isActive,
    required CustomPainter iconPainter,
    required VoidCallback onTap,
    bool hasDropdown = false,
  }) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 34,
          height: 25,
          margin: const EdgeInsets.symmetric(vertical: 0.5),
          decoration: BoxDecoration(
            color: isActive
                ? (viewModel.isLightBackground ? const Color(0xFF0284C7).withValues(alpha: 0.16) : const Color(0xFF0284C7).withValues(alpha: 0.22))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isActive ? (viewModel.isLightBackground ? const Color(0xFF0284C7) : const Color(0xFF38BDF8)) : Colors.transparent,
              width: 1.2,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(20, 20),
                painter: iconPainter,
              ),
              if (hasDropdown)
                const Positioned(
                  right: 1,
                  bottom: 1,
                  child: Icon(
                    Icons.arrow_drop_down,
                    size: 9,
                    color: Color(0xFF94A3B8),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMaterialsQuickPicker(BuildContext context) {
    final part = viewModel.selectedPart;
    if (part == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select a 3D part first to apply finishes/materials.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final finishes = [
      {'name': 'Galvanized Steel', 'color': const Color(0xFF94A3B8)},
      {'name': 'Stainless 316', 'color': const Color(0xFFCBD5E1)},
      {'name': 'Powder Coated Black', 'color': const Color(0xFF1E293B)},
      {'name': 'Safety Yellow', 'color': const Color(0xFFFACC15)},
      {'name': 'Signal Red', 'color': const Color(0xFFEF4444)},
      {'name': 'Industrial Blue', 'color': const Color(0xFF0284C7)},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF18181E),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Apply Material: ${part.name}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: finishes.map((f) {
                    final color = f['color'] as Color;
                    return InkWell(
                      onTap: () {
                        part.color = color;
                        viewModel.notifyDocChanged();
                        Navigator.pop(ctx);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF22222A),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: color, width: 1.5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(width: 12, height: 12, color: color),
                            const SizedBox(width: 6),
                            Text(f['name'] as String, style: const TextStyle(color: Colors.white, fontSize: 11)),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showScaleDialog(BuildContext context) {
    final part = viewModel.selectedPart;
    if (part == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a part to adjust scale/dimensions.')),
      );
      return;
    }

    final ctrl = TextEditingController(text: part.length.toStringAsFixed(0));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF18181E),
        title: Text('Scale Length: ${part.name}', style: const TextStyle(color: Colors.white, fontSize: 13)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Length (mm)',
                labelStyle: TextStyle(color: Color(0xFF94A3B8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final val = double.tryParse(ctrl.text);
              if (val != null && val > 0) {
                viewModel.updatePartDimensions(part.id, length: val);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  void _showMeasureInfo(BuildContext context) {
    final part = viewModel.selectedPart;
    final info = part != null
        ? 'Selected: ${part.name}\nLength: ${part.length}mm | Height: ${part.height}mm | Flange: ${part.flangeWidth}mm'
        : 'Tape Measure Tool Active\nClick any part face to inspect exact dimensional tolerances.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(info), duration: const Duration(seconds: 3)),
    );
  }
}

// ============================================================================
// MICRO-PAINTERS MATCHING SCREENSHOT SS2
// ============================================================================

/// 1. Select Tool: Cursor Arrow in classic CAD cyan/dark outline
class _SelectIconPainter extends CustomPainter {
  const _SelectIconPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()
      ..moveTo(4, 2)
      ..lineTo(4, 18)
      ..lineTo(8, 14)
      ..lineTo(12, 20)
      ..lineTo(14, 19)
      ..lineTo(10, 13)
      ..lineTo(15, 13)
      ..close();

    final fill = Paint()
      ..color = const Color(0xFF0284C7)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    canvas.drawPath(p, fill);
    canvas.drawPath(p, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 2. Paint Bucket Tool: Bucket pouring blue liquid
class _PaintBucketIconPainter extends CustomPainter {
  const _PaintBucketIconPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = const Color(0xFF38BDF8)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    final fill = Paint()
      ..color = const Color(0xFF0284C7)
      ..style = PaintingStyle.fill;

    // Tilted bucket body
    final b = Path()
      ..moveTo(6, 7)
      ..lineTo(14, 3)
      ..lineTo(18, 12)
      ..lineTo(10, 16)
      ..close();
    canvas.drawPath(b, stroke);

    // Liquid pouring out
    final spill = Path()
      ..moveTo(5, 7)
      ..quadraticBezierTo(2, 13, 4, 18)
      ..quadraticBezierTo(7, 16, 6, 7)
      ..close();
    canvas.drawPath(spill, fill);

    // Droplet
    canvas.drawCircle(const Offset(4, 20), 1.2, fill);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 3. Pencil Tool: Red pencil with sharp point
class _PencilIconPainter extends CustomPainter {
  const _PencilIconPainter();
  @override
  void paint(Canvas canvas, Size size) {
    // Red pencil body tilted
    final body = Path()
      ..moveTo(17, 4)
      ..lineTo(19, 6)
      ..lineTo(8, 17)
      ..lineTo(6, 15)
      ..close();

    final redPaint = Paint()
      ..color = const Color(0xFFEF4444)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawPath(body, redPaint);

    // Tip
    final tip = Path()
      ..moveTo(6, 15)
      ..lineTo(8, 17)
      ..lineTo(4, 19)
      ..close();
    final blackPaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.fill;
    canvas.drawPath(tip, blackPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 4. Rectangle Tool: Blue square with diagonal line and red corner dots
class _RectangleIconPainter extends CustomPainter {
  const _RectangleIconPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = const Color(0xFF38BDF8)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    const rect = Rect.fromLTWH(4, 4, 14, 14);
    canvas.drawRect(rect, stroke);
    canvas.drawLine(const Offset(4, 18), const Offset(18, 4), stroke);

    final dot = Paint()
      ..color = const Color(0xFFEF4444)
      ..style = PaintingStyle.fill;
    final blueDot = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(const Offset(4, 18), 1.8, blueDot);
    canvas.drawCircle(const Offset(18, 4), 2.0, dot);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 5. Circle Tool: Blue circle with center dot and red perimeter dot
class _CircleIconPainter extends CustomPainter {
  const _CircleIconPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = const Color(0xFF38BDF8)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    const center = Offset(11, 11);
    canvas.drawCircle(center, 7.5, stroke);

    // Radius line
    canvas.drawLine(center, const Offset(16.5, 5.5), stroke);

    final centerDot = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 1.8, centerDot);

    final redDot = Paint()
      ..color = const Color(0xFFEF4444)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(16.5, 5.5), 2.0, redDot);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 6. Arc Tool: 2-point arc with radius dots
class _ArcIconPainter extends CustomPainter {
  const _ArcIconPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = const Color(0xFF38BDF8)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    final arcPath = Path()
      ..moveTo(4, 16)
      ..quadraticBezierTo(16, 16, 16, 4);
    canvas.drawPath(arcPath, stroke);

    // Straight baseline
    canvas.drawLine(const Offset(4, 16), const Offset(4, 4), stroke);
    canvas.drawLine(const Offset(4, 16), const Offset(16, 4), stroke);

    final darkDot = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.fill;
    final redDot = Paint()
      ..color = const Color(0xFFEF4444)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(const Offset(4, 16), 1.8, darkDot);
    canvas.drawCircle(const Offset(4, 4), 1.8, darkDot);
    canvas.drawCircle(const Offset(16, 4), 2.0, redDot);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 7. Spline / Slot Tool: Curve with anchor nodes
class _SplineSlotIconPainter extends CustomPainter {
  const _SplineSlotIconPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = const Color(0xFF38BDF8)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    final curve = Path()
      ..moveTo(4, 16)
      ..cubicTo(10, 18, 12, 6, 18, 8);
    canvas.drawPath(curve, stroke);

    canvas.drawLine(const Offset(4, 16), const Offset(12, 11), stroke);

    final darkDot = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.fill;
    final redDot = Paint()
      ..color = const Color(0xFFEF4444)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(const Offset(4, 16), 1.8, darkDot);
    canvas.drawCircle(const Offset(12, 11), 1.8, darkDot);
    canvas.drawCircle(const Offset(18, 8), 2.0, redDot);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 8. Move Tool: 4-Way Red Cross Arrows
class _MoveIconPainter extends CustomPainter {
  const _MoveIconPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFEF4444)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.square;

    canvas.drawLine(const Offset(4, 11), const Offset(18, 11), paint);
    canvas.drawLine(const Offset(11, 4), const Offset(11, 18), paint);

    // Arrow heads
    final arrow = Paint()
      ..color = const Color(0xFFEF4444)
      ..style = PaintingStyle.fill;

    // Up
    canvas.drawPath(Path()..moveTo(11, 2)..lineTo(9, 5)..lineTo(13, 5)..close(), arrow);
    // Down
    canvas.drawPath(Path()..moveTo(11, 20)..lineTo(9, 17)..lineTo(13, 17)..close(), arrow);
    // Left
    canvas.drawPath(Path()..moveTo(2, 11)..lineTo(5, 9)..lineTo(5, 13)..close(), arrow);
    // Right
    canvas.drawPath(Path()..moveTo(20, 11)..lineTo(17, 9)..lineTo(17, 13)..close(), arrow);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 9. Rotate Tool: Circular Red Arrows
class _RotateIconPainter extends CustomPainter {
  const _RotateIconPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = const Color(0xFFEF4444)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;

    final rect = Rect.fromCircle(center: const Offset(11, 11), radius: 6.5);
    canvas.drawArc(rect, 0.4, 2.3, false, stroke);
    canvas.drawArc(rect, math.pi + 0.4, 2.3, false, stroke);

    final arrow = Paint()
      ..color = const Color(0xFFEF4444)
      ..style = PaintingStyle.fill;

    // Arrow tip 1
    canvas.drawPath(Path()..moveTo(17, 10)..lineTo(19, 13)..lineTo(15, 13)..close(), arrow);
    // Arrow tip 2
    canvas.drawPath(Path()..moveTo(5, 12)..lineTo(3, 9)..lineTo(7, 9)..close(), arrow);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 10. Scale Tool: Blue rectangle with red diagonal expand arrow
class _ScaleIconPainter extends CustomPainter {
  const _ScaleIconPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = const Color(0xFF38BDF8)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    canvas.drawRect(const Rect.fromLTWH(4, 6, 12, 12), stroke);
    canvas.drawRect(const Rect.fromLTWH(4, 6, 6, 6), stroke);

    // Diagonal expand arrow
    final redPaint = Paint()
      ..color = const Color(0xFFEF4444)
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(10, 12), const Offset(17, 5), redPaint);

    final arrow = Paint()
      ..color = const Color(0xFFEF4444)
      ..style = PaintingStyle.fill;
    canvas.drawPath(Path()..moveTo(18, 4)..lineTo(14, 4)..lineTo(18, 8)..close(), arrow);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 11. Tape Measure Tool: Measuring body with red reel
class _TapeMeasureIconPainter extends CustomPainter {
  const _TapeMeasureIconPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final body = Path()
      ..moveTo(5, 17)
      ..lineTo(14, 17)
      ..quadraticBezierTo(18, 17, 18, 12)
      ..quadraticBezierTo(18, 7, 13, 7)
      ..lineTo(7, 7)
      ..quadraticBezierTo(5, 7, 5, 10)
      ..close();

    final bodyPaint = Paint()
      ..color = const Color(0xFF0284C7)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    canvas.drawPath(body, bodyPaint);

    // Red center button
    final red = Paint()..color = const Color(0xFFEF4444);
    canvas.drawCircle(const Offset(11, 12), 2.5, red);

    // Tape tongue
    final tape = Paint()
      ..color = const Color(0xFFF59E0B)
      ..strokeWidth = 1.5;
    canvas.drawLine(const Offset(5, 17), const Offset(2, 17), tape);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 12. Protractor Tool: Half-circle with angle markings
class _ProtractorIconPainter extends CustomPainter {
  const _ProtractorIconPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = const Color(0xFF0369A1)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    final arc = Path()
      ..moveTo(4, 15)
      ..arcToPoint(const Offset(18, 15), radius: const Radius.circular(7))
      ..close();
    canvas.drawPath(arc, stroke);

    // Center cutout
    canvas.drawCircle(const Offset(11, 15), 2.2, stroke);

    // Degree tick marks
    final ticks = Paint()
      ..color = const Color(0xFF0369A1)
      ..strokeWidth = 0.8;
    canvas.drawLine(const Offset(11, 8), const Offset(11, 10), ticks);
    canvas.drawLine(const Offset(6, 11), const Offset(7.5, 12), ticks);
    canvas.drawLine(const Offset(16, 11), const Offset(14.5, 12), ticks);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 13. Zoom Tool: Magnifying glass
class _ZoomIconPainter extends CustomPainter {
  const _ZoomIconPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = const Color(0xFF0284C7)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(const Offset(10, 9), 5.5, stroke);
    canvas.drawLine(const Offset(14, 13), const Offset(19, 18), stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 14. Zoom Extents Tool: Magnifier with 4 outward red corner arrows
class _ZoomExtentsIconPainter extends CustomPainter {
  const _ZoomExtentsIconPainter();
  @override
  void paint(Canvas canvas, Size size) {
    // Center small lens
    final stroke = Paint()
      ..color = const Color(0xFF0284C7)
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(const Offset(11, 11), 3.5, stroke);
    canvas.drawLine(const Offset(13.5, 13.5), const Offset(17, 17), stroke);

    // 4 outward red arrows
    final red = Paint()
      ..color = const Color(0xFFEF4444)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    // Top-left
    canvas.drawLine(const Offset(5, 5), const Offset(2, 2), red);
    // Top-right
    canvas.drawLine(const Offset(17, 5), const Offset(20, 2), red);
    // Bottom-left
    canvas.drawLine(const Offset(5, 17), const Offset(2, 20), red);
    // Bottom-right
    canvas.drawLine(const Offset(17, 17), const Offset(20, 20), red);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Auto-Span Bridge Tool Icon: Two parallel vertical stiles bridged by a horizontal rung with weld joints
class _BridgeIconPainter extends CustomPainter {
  const _BridgeIconPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final railPaint = Paint()
      ..color = const Color(0xFF64748B)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    final bridgePaint = Paint()
      ..color = const Color(0xFF38BDF8)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final weldDot = Paint()
      ..color = const Color(0xFFEF4444)
      ..style = PaintingStyle.fill;

    // Left stile
    canvas.drawLine(const Offset(5, 3), const Offset(5, 19), railPaint);
    // Right stile
    canvas.drawLine(const Offset(17, 3), const Offset(17, 19), railPaint);
    // Spanning bridge rung
    canvas.drawLine(const Offset(5, 11), const Offset(17, 11), bridgePaint);

    // Dual fillet weld dots at connections
    canvas.drawCircle(const Offset(5, 11), 2.0, weldDot);
    canvas.drawCircle(const Offset(17, 11), 2.0, weldDot);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Fillet Weld Tool Icon: 90-degree corner joint with continuous fillet weld bead and torch spark
class _WeldIconPainter extends CustomPainter {
  const _WeldIconPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final metalPaint = Paint()
      ..color = const Color(0xFF64748B)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.square;

    // Vertical metal plate
    canvas.drawLine(const Offset(6, 4), const Offset(6, 17), metalPaint);
    // Base metal plate
    canvas.drawLine(const Offset(4, 17), const Offset(19, 17), metalPaint);

    // Fillet weld bead (smooth concave bead fillet)
    final beadPaint = Paint()
      ..color = const Color(0xFFF59E0B)
      ..style = PaintingStyle.fill;
    final beadPath = Path()
      ..moveTo(6, 11)
      ..quadraticBezierTo(9, 14, 12, 17)
      ..lineTo(6, 17)
      ..close();
    canvas.drawPath(beadPath, beadPaint);

    // Weld glow highlight
    final glowPaint = Paint()
      ..color = const Color(0xFFFDE047)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(8, 15), 1.5, glowPaint);

    // Spark / arc flash
    final sparkPaint = Paint()
      ..color = const Color(0xFF38BDF8)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(11, 10), const Offset(15, 6), sparkPaint);
    canvas.drawLine(const Offset(13, 13), const Offset(18, 11), sparkPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Magnetic Tool Icon: Horseshoe magnet with Red (North) and Cyan (South) poles and magnetic flux lines
class _MagneticIconPainter extends CustomPainter {
  const _MagneticIconPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final northPaint = Paint()
      ..color = const Color(0xFFEF4444)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.butt;

    final southPaint = Paint()
      ..color = const Color(0xFF38BDF8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.butt;

    final basePaint = Paint()
      ..color = const Color(0xFF64748B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8;

    // Draw U-shape bottom arch
    final baseRect = Rect.fromCircle(center: const Offset(11, 13), radius: 6.5);
    canvas.drawArc(baseRect, 0, math.pi, false, basePaint);

    // Left straight pole (North - Red)
    canvas.drawLine(const Offset(4.5, 6), const Offset(4.5, 13), northPaint);
    // Right straight pole (South - Cyan)
    canvas.drawLine(const Offset(17.5, 6), const Offset(17.5, 13), southPaint);

    // Silver pole tips
    final tipPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(const Offset(4.5, 4.5), const Offset(4.5, 6), tipPaint);
    canvas.drawLine(const Offset(17.5, 4.5), const Offset(17.5, 6), tipPaint);

    // Magnetic flux arc between poles
    final fluxPaint = Paint()
      ..color = const Color(0xFFA855F7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final fluxRect = Rect.fromCircle(center: const Offset(11, 5), radius: 4);
    canvas.drawArc(fluxRect, math.pi * 0.9, math.pi * 1.2, false, fluxPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Theme Mode Toggle Icon: Solar Sun (amber/gold rays) for Light mode, Crescent Moon (cyan/stars) for Dark mode.
class _ThemeModeIconPainter extends CustomPainter {
  final bool isLight;
  const _ThemeModeIconPainter({required this.isLight});

  @override
  void paint(Canvas canvas, Size size) {
    if (isLight) {
      // Sun icon
      final sunFill = Paint()
        ..color = const Color(0xFFD97706)
        ..style = PaintingStyle.fill;
      final rayPaint = Paint()
        ..color = const Color(0xFFF59E0B)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;

      final center = Offset(size.width / 2, size.height / 2);
      canvas.drawCircle(center, 4.2, sunFill);

      // 8 solar rays
      const r1 = 6.2;
      const r2 = 9.2;
      for (int i = 0; i < 8; i++) {
        final angle = i * math.pi / 4;
        final dx = math.cos(angle);
        final dy = math.sin(angle);
        canvas.drawLine(
          Offset(center.dx + dx * r1, center.dy + dy * r1),
          Offset(center.dx + dx * r2, center.dy + dy * r2),
          rayPaint,
        );
      }
    } else {
      // Sleek crescent moon icon
      final moonPaint = Paint()
        ..color = const Color(0xFF38BDF8)
        ..style = PaintingStyle.fill;

      final path = Path()
        ..moveTo(14, 4)
        ..arcToPoint(
          const Offset(14, 18),
          radius: const Radius.circular(7.5),
          clockwise: true,
        )
        ..arcToPoint(
          const Offset(14, 4),
          radius: const Radius.circular(5.8),
          clockwise: false,
        )
        ..close();
      canvas.drawPath(path, moonPaint);

      final starPaint = Paint()
        ..color = const Color(0xFFFACC15)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(const Offset(6.5, 7.5), 1.2, starPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ThemeModeIconPainter oldDelegate) =>
      oldDelegate.isLight != isLight;
}

/// Camera Orbit Tool Icon Painter (SS1)
/// Matches SketchUp Orbit icon: Red circular arrow rotating around a central vertical axis line
class OrbitIconPainter extends CustomPainter {
  const OrbitIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // 1. Central vertical axis line (dark slate/blue)
    final axisPaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx, 2.5), Offset(cx, size.height - 2.5), axisPaint);

    // 2. Red 3D Orbit Loop (ellipse)
    final redPaint = Paint()
      ..color = const Color(0xFFDC2626)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final rect = Rect.fromCenter(center: Offset(cx, cy), width: size.width - 4, height: 9.5);
    canvas.drawOval(rect, redPaint);

    // 3. Arrowheads on front & back curve
    final arrowPaint = Paint()
      ..color = const Color(0xFFDC2626)
      ..style = PaintingStyle.fill;

    // Front bottom arrowhead pointing right
    final arrowTip1 = Offset(cx + 3.0, cy + 4.8);
    final p1 = Path()
      ..moveTo(arrowTip1.dx + 3.5, arrowTip1.dy)
      ..lineTo(arrowTip1.dx - 1.5, arrowTip1.dy - 3.0)
      ..lineTo(arrowTip1.dx - 1.5, arrowTip1.dy + 3.0)
      ..close();
    canvas.drawPath(p1, arrowPaint);

    // Back top arrowhead pointing left
    final arrowTip2 = Offset(cx - 3.0, cy - 4.8);
    final p2 = Path()
      ..moveTo(arrowTip2.dx - 3.5, arrowTip2.dy)
      ..lineTo(arrowTip2.dx + 1.5, arrowTip2.dy - 3.0)
      ..lineTo(arrowTip2.dx + 1.5, arrowTip2.dy + 3.0)
      ..close();
    canvas.drawPath(p2, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Camera Pan Tool Icon Painter (SS1)
/// Matches SketchUp Pan icon: Hand with red horizontal double-arrow above the fingers
class PanIconPainter extends CustomPainter {
  const PanIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;

    // 1. Red double-headed horizontal arrow (⟷) above the hand
    const yArrow = 4.0;
    final arrowPaint = Paint()
      ..color = const Color(0xFFDC2626)
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(4.0, yArrow), Offset(size.width - 4.0, yArrow), arrowPaint);

    final arrowHeadPaint = Paint()
      ..color = const Color(0xFFDC2626)
      ..style = PaintingStyle.fill;

    // Left arrowhead ◄
    final leftHead = Path()
      ..moveTo(2.5, yArrow)
      ..lineTo(6.5, yArrow - 2.6)
      ..lineTo(6.5, yArrow + 2.6)
      ..close();
    canvas.drawPath(leftHead, arrowHeadPaint);

    // Right arrowhead ►
    final rightHead = Path()
      ..moveTo(size.width - 2.5, yArrow)
      ..lineTo(size.width - 6.5, yArrow - 2.6)
      ..lineTo(size.width - 6.5, yArrow + 2.6)
      ..close();
    canvas.drawPath(rightHead, arrowHeadPaint);

    // 2. Hand with outstretched palm & fingers (SS1)
    final handBorderPaint = Paint()
      ..color = const Color(0xFF0369A1)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    final handFillPaint = Paint()
      ..color = const Color(0xFFE0F2FE)
      ..style = PaintingStyle.fill;

    final handPath = Path()
      ..moveTo(cx - 4.5, size.height - 2.0)
      ..lineTo(cx + 4.5, size.height - 2.0)
      ..lineTo(cx + 5.5, size.height - 7.5)
      ..lineTo(cx + 6.0, size.height - 11.5)
      ..lineTo(cx + 4.2, size.height - 11.5)
      ..lineTo(cx + 3.8, size.height - 13.5)
      ..lineTo(cx + 2.0, size.height - 13.5)
      ..lineTo(cx + 1.5, size.height - 14.8)
      ..lineTo(cx - 0.5, size.height - 14.8)
      ..lineTo(cx - 1.0, size.height - 13.5)
      ..lineTo(cx - 2.8, size.height - 13.5)
      ..lineTo(cx - 3.8, size.height - 9.5)
      ..lineTo(cx - 6.5, size.height - 9.5)
      ..lineTo(cx - 6.0, size.height - 6.8)
      ..lineTo(cx - 4.8, size.height - 5.8)
      ..close();

    canvas.drawPath(handPath, handFillPaint);
    canvas.drawPath(handPath, handBorderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

