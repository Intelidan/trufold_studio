import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Painter that renders an authentic incandescent orange welding arc lamp at the torch tip,
/// illuminating the surrounding 3D viewport and metal entities with warm ambient light.
class AssemblyWeldLampPainter extends CustomPainter {
  final Offset? torchPosition;
  final bool isWelding;
  final double flickerPhase;

  AssemblyWeldLampPainter({
    required this.torchPosition,
    required this.isWelding,
    this.flickerPhase = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!isWelding || torchPosition == null) return;
    final pos = torchPosition!;

    // Dynamic arc flicker factor between 0.88 and 1.15
    final flicker = 0.95 + 0.12 * math.sin(flickerPhase * 37.0) + 0.08 * math.cos(flickerPhase * 73.0);

    // Layer 1: Broad soft ambient illumination field (spreads across adjacent metal rails)
    final outerRadius = 140.0 * flicker;
    final outerAmbientPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFF97316).withValues(alpha: 0.28),
          const Color(0xFFEA580C).withValues(alpha: 0.14),
          const Color(0xFFC2410C).withValues(alpha: 0.04),
          Colors.transparent,
        ],
        stops: const [0.0, 0.45, 0.75, 1.0],
      ).createShader(Rect.fromCircle(center: pos, radius: outerRadius))
      ..blendMode = BlendMode.screen;
    canvas.drawCircle(pos, outerRadius, outerAmbientPaint);

    // Layer 2: Concentrated warm fiery halogen bloom
    final midRadius = 55.0 * flicker;
    final midBloomPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFBBF24).withValues(alpha: 0.70),
          const Color(0xFFF97316).withValues(alpha: 0.40),
          Colors.transparent,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: pos, radius: midRadius))
      ..blendMode = BlendMode.screen;
    canvas.drawCircle(pos, midRadius, midBloomPaint);

    // Layer 3: High-heat molten plasma core
    final innerRadius = 18.0 * flicker;
    final innerCorePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFEF08A).withValues(alpha: 0.95),
          const Color(0xFFF59E0B).withValues(alpha: 0.65),
          Colors.transparent,
        ],
        stops: const [0.0, 0.6, 1.0],
      ).createShader(Rect.fromCircle(center: pos, radius: innerRadius))
      ..blendMode = BlendMode.plus;
    canvas.drawCircle(pos, innerRadius, innerCorePaint);

    // Layer 4: Focal white-hot electric arc spot
    final focalRadius = 5.5 * flicker;
    final focalPaint = Paint()
      ..color = const Color(0xFFFFFBEB)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);
    canvas.drawCircle(pos, focalRadius, focalPaint);

    // Subtle 4-axis starburst glare spike from electric arc
    final spikePaint = Paint()
      ..color = const Color(0xFFFFF7ED).withValues(alpha: 0.65)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final spikeLen = 22.0 * flicker;
    canvas.drawLine(pos - Offset(spikeLen, 0), pos + Offset(spikeLen, 0), spikePaint);
    canvas.drawLine(pos - Offset(0, spikeLen), pos + Offset(0, spikeLen), spikePaint);
  }

  @override
  bool shouldRepaint(covariant AssemblyWeldLampPainter old) {
    return old.isWelding != isWelding ||
        old.torchPosition != torchPosition ||
        old.flickerPhase != flickerPhase;
  }
}
