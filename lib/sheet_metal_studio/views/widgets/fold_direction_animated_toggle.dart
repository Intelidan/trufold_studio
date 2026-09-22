// =============================================================================
// fold_direction_animated_toggle.dart
//
// Creative & dramatic animated toggle for press-brake bend fold direction (+Z / -Z).
// Features:
// - Real-time animated 3D isometric sheet metal hinge visualizer
// - 3D perspective tilt flip animation during direction change
// - Dynamic dual-state glow gradients (Sky Blue for +Z UP vs Molten Amber for -Z DOWN)
// - Tactile spring-back press micro-interaction
// - 180° continuous spinning direction swap badge
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/fold_bend_line.dart';

/// Single, dramatic animated toggle button for switching fold direction
/// between +Z (UP) and -Z (DOWN).
class FoldDirectionAnimatedToggle extends StatefulWidget {
  final BendDirection direction;
  final ValueChanged<BendDirection> onToggle;
  final bool isFlange;

  const FoldDirectionAnimatedToggle({
    super.key,
    required this.direction,
    required this.onToggle,
    this.isFlange = false,
  });

  @override
  State<FoldDirectionAnimatedToggle> createState() =>
      _FoldDirectionAnimatedToggleState();
}

class _FoldDirectionAnimatedToggleState
    extends State<FoldDirectionAnimatedToggle>
    with TickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _curve;
  late final AnimationController _pressController;
  late final Animation<double> _scaleAnimation;

  double _rotationAngle = 0.0;
  bool _isHovered = false;

  bool get _isUp => widget.direction == BendDirection.up;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      value: _isUp ? 0.0 : 1.0,
    );
    _curve = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOutBack,
    );

    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void didUpdateWidget(covariant FoldDirectionAnimatedToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.direction != widget.direction) {
      if (_isUp) {
        _animController.animateTo(0.0, curve: Curves.easeInOutBack);
      } else {
        _animController.animateTo(1.0, curve: Curves.easeInOutBack);
      }
      _rotationAngle += math.pi;
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _pressController.dispose();
    super.dispose();
  }

  void _handleTap() {
    final nextDirection =
        _isUp ? BendDirection.down : BendDirection.up;
    widget.onToggle(nextDirection);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_curve, _scaleAnimation]),
      builder: (context, _) {
        final progress = _curve.value; // 0.0 = UP, 1.0 = DOWN

        // Interpolated theme colors
        final Color primaryColor = Color.lerp(
          const Color(0xFF0284C7), // Sky Blue for +Z UP
          const Color(0xFFD97706), // Amber for -Z DOWN
          progress,
        )!;

        final Color bgGradientStart = Color.lerp(
          const Color(0xFFF0F9FF),
          const Color(0xFFFFFBEB),
          progress,
        )!;

        final Color bgGradientEnd = Color.lerp(
          const Color(0xFFE0F2FE),
          const Color(0xFFFEF3C7),
          progress,
        )!;

        final Color borderColor = Color.lerp(
          const Color(0xFF38BDF8),
          const Color(0xFFF59E0B),
          progress,
        )!;

        // 3D perspective tilt: peaks at mid-transition (progress = 0.5)
        final tiltMagnitude = math.sin(progress * math.pi) * 0.22;
        final tiltDirection = _isUp ? -1.0 : 1.0;
        final tiltX = tiltMagnitude * tiltDirection;

        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            onTapDown: (_) => _pressController.forward(),
            onTapUp: (_) {
              _pressController.reverse();
              _handleTap();
            },
            onTapCancel: () => _pressController.reverse(),
            child: Transform.scale(
              scale: _scaleAnimation.value * (_isHovered ? 1.015 : 1.0),
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.002) // 3D perspective distortion
                  ..rotateX(tiltX),
                child: Container(
                  height: 42.0,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [bgGradientStart, bgGradientEnd],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(
                      color: _isHovered
                          ? primaryColor
                          : borderColor.withValues(alpha: 0.85),
                      width: _isHovered ? 1.8 : 1.4,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: primaryColor.withValues(
                          alpha: _isHovered ? 0.32 : 0.18,
                        ),
                        blurRadius: _isHovered ? 10.0 : 6.0,
                        spreadRadius: _isHovered ? 0.8 : 0.0,
                        offset: const Offset(0, 2.0),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // --- 1. Isometric 3D Folding Hinge Visualizer ---
                      SizedBox(
                        width: 30.0,
                        height: 28.0,
                        child: CustomPaint(
                          painter: _FoldHingePainter(
                            progress: progress,
                            activeColor: primaryColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // --- 2. Direction Label & Elevation Badge ---
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              progress < 0.5 ? '↑ (+Z) UP' : '↓ (-Z) DOWN',
                              style: TextStyle(
                                color: primaryColor,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              progress < 0.5
                                  ? 'SURFACE ▲ (Toward Viewer)'
                                  : 'REVERSE ▼ (Into Screen)',
                              style: TextStyle(
                                color: primaryColor.withValues(alpha: 0.78),
                                fontSize: 8.0,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),

                      // --- 3. Dramatic Flip Action Badge ---
                      Tooltip(
                        message: _isUp
                            ? 'Click to flip fold direction to -Z (DOWN)'
                            : 'Click to flip fold direction to +Z (UP)',
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          padding: const EdgeInsets.all(5.0),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: primaryColor.withValues(alpha: 0.4),
                              width: 1.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: primaryColor.withValues(alpha: 0.2),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: TweenAnimationBuilder<double>(
                            tween: Tween<double>(
                              begin: 0.0,
                              end: _rotationAngle,
                            ),
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeOutBack,
                            builder: (context, angle, child) {
                              return Transform.rotate(
                                angle: angle,
                                child: Icon(
                                  Icons.swap_vert_rounded,
                                  size: 15.0,
                                  color: primaryColor,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Isometric 3D Fold Hinge Painter
// -----------------------------------------------------------------------------

class _FoldHingePainter extends CustomPainter {
  final double progress; // 0.0 = UP (+Z), 1.0 = DOWN (-Z)
  final Color activeColor;

  _FoldHingePainter({required this.progress, required this.activeColor});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * 0.46;
    final cy = size.height * 0.50;

    // 1. Base plate (stationary sheet metal face in isometric perspective)
    final baseP1 = Offset(cx - 11.0, cy + 2.5);
    final baseP2 = Offset(cx, cy + 5.5);
    final baseP3 = Offset(cx, cy - 5.5);
    final baseP4 = Offset(cx - 11.0, cy - 8.5);

    final basePath = Path()
      ..moveTo(baseP1.dx, baseP1.dy)
      ..lineTo(baseP2.dx, baseP2.dy)
      ..lineTo(baseP3.dx, baseP3.dy)
      ..lineTo(baseP4.dx, baseP4.dy)
      ..close();

    final baseFill = Paint()
      ..color = const Color(0xFF94A3B8).withValues(alpha: 0.75)
      ..style = PaintingStyle.fill;
    canvas.drawPath(basePath, baseFill);

    final baseBorder = Paint()
      ..color = const Color(0xFF64748B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawPath(basePath, baseBorder);

    // 2. Center bend hinge line
    final hingePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(baseP2, baseP3, hingePaint);

    // 3. Dynamic folding flange:
    // When progress = 0.0 (+Z UP), flange elevation is -8.5 px (elevated up)
    // When progress = 1.0 (-Z DOWN), flange elevation is +8.5 px (dipped down)
    final foldDeltaY = (progress - 0.5) * 17.0;

    final flangeP1 = baseP2;
    final flangeP2 = Offset(cx + 11.0, cy + 5.5 + foldDeltaY);
    final flangeP3 = Offset(cx + 11.0, cy - 5.5 + foldDeltaY);
    final flangeP4 = baseP3;

    final flangePath = Path()
      ..moveTo(flangeP1.dx, flangeP1.dy)
      ..lineTo(flangeP2.dx, flangeP2.dy)
      ..lineTo(flangeP3.dx, flangeP3.dy)
      ..lineTo(flangeP4.dx, flangeP4.dy)
      ..close();

    final flangeGradient = LinearGradient(
      colors: [
        activeColor.withValues(alpha: 0.88),
        activeColor.withValues(alpha: 0.52),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ).createShader(Rect.fromPoints(flangeP1, flangeP3));

    final flangeFill = Paint()
      ..shader = flangeGradient
      ..style = PaintingStyle.fill;
    canvas.drawPath(flangePath, flangeFill);

    final flangeBorder = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawPath(flangePath, flangeBorder);

    // 4. Vector arrow glyph indicating Z-axis movement
    final arrowX = cx + 13.5;
    final arrowBaseY = cy + foldDeltaY * 0.45;
    final isUp = progress < 0.5;
    final arrowTipY = isUp ? arrowBaseY - 6.0 : arrowBaseY + 6.0;

    final arrowPaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(arrowX, arrowBaseY),
      Offset(arrowX, arrowTipY),
      arrowPaint,
    );

    final headDir = isUp ? -1.0 : 1.0;
    final headPath = Path()
      ..moveTo(arrowX - 2.5, arrowTipY - headDir * 3.0)
      ..lineTo(arrowX, arrowTipY)
      ..lineTo(arrowX + 2.5, arrowTipY - headDir * 3.0);
    canvas.drawPath(headPath, arrowPaint);
  }

  @override
  bool shouldRepaint(_FoldHingePainter old) =>
      old.progress != progress || old.activeColor != activeColor;
}
