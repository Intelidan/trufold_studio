// =============================================================================
// trufold_splash_screen.dart
//
// Interactive Startup Splash Screen for truFold Studio.
// Showcases the "Concept 3: Hinged Planar 't-F'" 3D folding animation,
// dynamic laser-cut trace, technical CAD blueprint aesthetics, and system loader.
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';

import 'trufold_3d_icon.dart';

/// Full-featured animated splash screen for truFold Studio.
class TruFoldSplashScreen extends StatefulWidget {
  /// Callback triggered when the startup sequence completes.
  final VoidCallback? onInitializationComplete;

  /// Duration before triggering initialization complete.
  final Duration totalDuration;

  /// Whether to allow the user to click to skip the splash animation.
  final bool allowTapToSkip;

  const TruFoldSplashScreen({super.key, this.onInitializationComplete, this.totalDuration = const Duration(milliseconds: 3200), this.allowTapToSkip = true});

  @override
  State<TruFoldSplashScreen> createState() => _TruFoldSplashScreenState();
}

class _TruFoldSplashScreenState extends State<TruFoldSplashScreen> with TickerProviderStateMixin {
  late AnimationController _mainController;
  late Animation<double> _laserTraceAnim;
  late Animation<double> _foldProgressAnim;
  late Animation<double> _textFadeAnim;
  late Animation<Offset> _textSlideAnim;
  late Animation<double> _statusFadeAnim;

  int _statusIndex = 0;
  Timer? _statusTimer;

  static const List<String> _statusMessages = [
    'Loading Sheet Metal Kinematics Engine...',
    'Calibrating Direct Dimension Solver...',
    'Initializing 3D Folding Geometry...',
    'Starting truFold Studio...',
  ];

  @override
  void initState() {
    super.initState();

    _mainController = AnimationController(vsync: this, duration: widget.totalDuration);

    // 1. Laser cut outline trace: 0% -> 30%
    _laserTraceAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.32, curve: Curves.easeInOut),
      ),
    );

    // 2. 3D Folding of the 'F' flap (0° -> 75°): 28% -> 72%
    _foldProgressAnim = Tween<double>(begin: 0.0, end: 75.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.28, 0.72, curve: Curves.easeOutBack),
      ),
    );

    // 3. Logo Typography Fade & Slide: 45% -> 80%
    _textFadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.45, 0.78, curve: Curves.easeOut),
      ),
    );
    _textSlideAnim = Tween<Offset>(begin: const Offset(0.0, 0.15), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.45, 0.78, curve: Curves.easeOutCubic),
      ),
    );

    // 4. Status Bar & Loading: 35% -> 95%
    _statusFadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.35, 0.55, curve: Curves.easeIn),
      ),
    );

    _mainController.forward();

    // Rotate status messages smoothly
    _statusTimer = Timer.periodic(const Duration(milliseconds: 700), (timer) {
      if (mounted && _statusIndex < _statusMessages.length - 1) {
        setState(() {
          _statusIndex++;
        });
      }
    });

    _mainController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onInitializationComplete?.call();
      }
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _mainController.dispose();
    super.dispose();
  }

  void _skip() {
    if (widget.allowTapToSkip) {
      widget.onInitializationComplete?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _skip,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0F19), // Deep CAD Obsidian
        body: Stack(
          children: [
            // 1. Animated Blueprint CAD Grid Background
            Positioned.fill(child: CustomPaint(painter: _BlueprintGridBackgroundPainter())),

            // 2. Radial Ambient Glow behind the logo
            Positioned.fill(
              child: Center(
                child: Container(
                  width: 500,
                  height: 500,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [const Color(0xFF38BDF8).withValues(alpha: 0.12), const Color(0xFF0284C7).withValues(alpha: 0.04), Colors.transparent],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
              ),
            ),

            // 3. Central Brand Composition
            Center(
              child: AnimatedBuilder(
                animation: _mainController,
                builder: (context, child) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // True 3D Folding Icon
                      SizedBox(
                        width: 170,
                        height: 170,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Glowing Laser Perimeter Trace Ring
                            if (_laserTraceAnim.value < 1.0)
                              CustomPaint(
                                size: const Size(170, 170),
                                painter: _LaserCutTracePainter(progress: _laserTraceAnim.value),
                              ),

                            // True 3D Folding Icon
                            TruFold3DIcon(
                              size: 155,
                              isAnimated: false,
                              fixedFoldAngleDeg: _foldProgressAnim.value,
                              showGrid: false,
                              showAnnotations: true,
                              sheetThickness: 2.8,
                              tColor: const Color(0xFF38BDF8), // Radiant Sky Blue
                              fColor: const Color(0xFF64748B), // Precision Steel Slate
                              accentColor: const Color(0xFFF97316),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Typography: "truFold by danish"
                      FadeTransition(
                        opacity: _textFadeAnim,
                        child: SlideTransition(
                          position: _textSlideAnim,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    'truFold',
                                    style: const TextStyle(
                                      color: Color(0xFFF8FAFC),
                                      fontSize: 40,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -1.0,
                                      fontFamily: 'sans-serif',
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0284C7).withValues(alpha: 0.25),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.6), width: 1.0),
                                    ),
                                    child: const Text(
                                      'STUDIO',
                                      style: TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.4),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'by danish',
                                style: TextStyle(
                                  color: const Color(0xFF94A3B8),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 2.2,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            // 4. Bottom Status & Progress Indicator
            Positioned(
              bottom: 48,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _statusFadeAnim,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Precision Progress Line
                      SizedBox(
                        width: 220,
                        height: 2.5,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: _mainController.value,
                            backgroundColor: const Color(0xFF1E293B),
                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF38BDF8)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Animated Status Text
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: Text(
                          _statusMessages[_statusIndex],
                          key: ValueKey<int>(_statusIndex),
                          style: const TextStyle(color: Color(0xFF64748B), fontSize: 11.5, fontFamily: 'monospace', letterSpacing: 0.3),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Draws an aesthetic CAD Blueprint Grid in dark mode.
class _BlueprintGridBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final majorPaint = Paint()
      ..color = const Color(0xFF1E293B).withValues(alpha: 0.65)
      ..strokeWidth = 0.9;

    final minorPaint = Paint()
      ..color = const Color(0xFF131B2E).withValues(alpha: 0.85)
      ..strokeWidth = 0.5;

    const minorStep = 16.0;
    const majorStep = minorStep * 4;

    for (double x = 0; x <= size.width; x += minorStep) {
      final isMajor = (x % majorStep).abs() < 1.0;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), isMajor ? majorPaint : minorPaint);
    }

    for (double y = 0; y <= size.height; y += minorStep) {
      final isMajor = (y % majorStep).abs() < 1.0;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), isMajor ? majorPaint : minorPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Draws a laser cut trace around the perimeter during phase 1.
class _LaserCutTracePainter extends CustomPainter {
  final double progress;

  _LaserCutTracePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.0) return;

    final rect = Rect.fromCenter(center: Offset(size.width / 2.0, size.height / 2.0), width: size.width * 0.92, height: size.height * 0.92);

    final path = Path()..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)));
    final pathMetric = path.computeMetrics().first;
    final extractPath = pathMetric.extractPath(0, pathMetric.length * progress);

    final tracePaint = Paint()
      ..color = const Color(0xFF38BDF8).withValues(alpha: 0.8)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    canvas.drawPath(extractPath, tracePaint);

    // Laser spark dot at cutting head
    final tangent = pathMetric.getTangentForOffset(pathMetric.length * progress);
    if (tangent != null) {
      final sparkCenter = tangent.position;
      final glowPaint = Paint()
        ..color = const Color(0xFF38BDF8).withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(sparkCenter, 5, glowPaint);

      final corePaint = Paint()..color = Colors.white;
      canvas.drawCircle(sparkCenter, 2.2, corePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LaserCutTracePainter old) => old.progress != progress;
}
