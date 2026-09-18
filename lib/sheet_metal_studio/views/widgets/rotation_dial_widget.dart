// =============================================================================
// rotation_dial_widget.dart
//
// Interactive Rotation Dial for truFold Studio by Danish.
// Allows intuitive circular dragging to rotate CNC perforation patterns and hole
// features to any angle (0° to 360°), with tick marks, degree badge, and presets.
// =============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';

class RotationDialWidget extends StatefulWidget {
  final double angleDeg;
  final ValueChanged<double> onAngleChanged;
  final String label;

  const RotationDialWidget({
    super.key,
    required this.angleDeg,
    required this.onAngleChanged,
    this.label = 'Hole Rotation',
  });

  @override
  State<RotationDialWidget> createState() => _RotationDialWidgetState();
}

class _RotationDialWidgetState extends State<RotationDialWidget> {
  late TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(
      text: widget.angleDeg.round().toString(),
    );
  }

  @override
  void didUpdateWidget(covariant RotationDialWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.angleDeg - widget.angleDeg).abs() > 0.5) {
      _textController.text = widget.angleDeg.round().toString();
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _handlePanUpdate(Offset localPos, Size size) {
    final center = Offset(size.width / 2.0, size.height / 2.0);
    final dx = localPos.dx - center.dx;
    final dy = localPos.dy - center.dy;

    var rad = math.atan2(dy, dx);
    var deg = rad * 180.0 / math.pi;
    if (deg < 0) deg += 360.0;

    final rounded = (deg / 5.0).round() * 5.0;
    final normalized = (rounded % 360.0);

    widget.onAngleChanged(normalized);
  }

  @override
  Widget build(BuildContext context) {
    const dialSize = 64.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.label.toUpperCase(),
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 8.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFFBAE6FD)),
                ),
                child: Text(
                  '${widget.angleDeg.round()}°',
                  style: const TextStyle(
                    color: Color(0xFF0284C7),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          Row(
            children: [
              // Circular Rotation Dial
              GestureDetector(
                onPanStart: (d) => _handlePanUpdate(d.localPosition, const Size(dialSize, dialSize)),
                onPanUpdate: (d) => _handlePanUpdate(d.localPosition, const Size(dialSize, dialSize)),
                child: SizedBox(
                  width: dialSize,
                  height: dialSize,
                  child: CustomPaint(
                    painter: _DialPainter(angleDeg: widget.angleDeg),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Quick Angle Presets & Manual Input
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [0.0, 45.0, 90.0, 180.0].map((preset) {
                        final isSelected = (widget.angleDeg - preset).abs() < 2.0;
                        return InkWell(
                          onTap: () => widget.onAngleChanged(preset),
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFF0284C7) : Colors.white,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isSelected ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1),
                              ),
                            ),
                            child: Text(
                              '${preset.round()}°',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: isSelected ? Colors.white : const Color(0xFF334155),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        const Text(
                          'Angle: ',
                          style: TextStyle(fontSize: 9, color: Color(0xFF64748B)),
                        ),
                        SizedBox(
                          width: 48,
                          height: 22,
                          child: TextField(
                            controller: _textController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold),
                            decoration: const InputDecoration(
                              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              border: OutlineInputBorder(),
                              isDense: true,
                              suffixText: '°',
                              suffixStyle: TextStyle(fontSize: 8.5),
                            ),
                            onSubmitted: (val) {
                              final parsed = double.tryParse(val);
                              if (parsed != null) {
                                widget.onAngleChanged(parsed % 360.0);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  final double angleDeg;

  const _DialPainter({required this.angleDeg});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2.0, size.height / 2.0);
    final radius = (size.width / 2.0) - 2.0;

    // Dial background disc
    final bgPaint = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFFFFFFFF), Color(0xFFE2E8F0)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, bgPaint);

    // Dial rim border
    final rimPaint = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, radius, rimPaint);

    // Tick marks every 45°
    final tickPaint = Paint()
      ..color = const Color(0xFF94A3B8)
      ..strokeWidth = 1.0;
    final majorTickPaint = Paint()
      ..color = const Color(0xFF0284C7)
      ..strokeWidth = 1.6;

    for (int deg = 0; deg < 360; deg += 45) {
      final isMajor = deg % 90 == 0;
      final rad = deg * math.pi / 180.0;
      final innerR = isMajor ? radius - 6.0 : radius - 4.0;
      final p1 = Offset(center.dx + math.cos(rad) * innerR, center.dy + math.sin(rad) * innerR);
      final p2 = Offset(center.dx + math.cos(rad) * radius, center.dy + math.sin(rad) * radius);
      canvas.drawLine(p1, p2, isMajor ? majorTickPaint : tickPaint);
    }

    // Indicator Needle / Pointer
    final angleRad = angleDeg * math.pi / 180.0;
    final needleEnd = Offset(
      center.dx + math.cos(angleRad) * (radius - 5.0),
      center.dy + math.sin(angleRad) * (radius - 5.0),
    );

    final needlePaint = Paint()
      ..color = const Color(0xFF0284C7)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, needleEnd, needlePaint);

    // Center pivot knob
    final centerPaint = Paint()..color = const Color(0xFF0F172A);
    canvas.drawCircle(center, 3.5, centerPaint);

    // Outer needle knob
    final knobPaint = Paint()..color = const Color(0xFF38BDF8);
    canvas.drawCircle(needleEnd, 3.0, knobPaint);
  }

  @override
  bool shouldRepaint(covariant _DialPainter oldDelegate) =>
      oldDelegate.angleDeg != angleDeg;
}
