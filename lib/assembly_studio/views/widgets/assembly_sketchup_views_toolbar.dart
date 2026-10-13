import 'package:flutter/material.dart';
import '../../viewmodels/assembly_studio_viewmodel.dart';

/// Authentic SketchUp-style standard views horizontal toolbar matching Screenshot SS3.
/// Features Iso, Top, Front, Right, Back, Left, and Bottom views with house icons.
class AssemblySketchupViewsToolbar extends StatelessWidget {
  final AssemblyStudioViewModel viewModel;
  final VoidCallback? onResetView;
  final VoidCallback? onCenterAxes;
  final Function(DragUpdateDetails)? onDragUpdate;

  const AssemblySketchupViewsToolbar({
    super.key,
    required this.viewModel,
    this.onResetView,
    this.onCenterAxes,
    this.onDragUpdate,
  });

  void _selectView(SketchUpStandardView view) {
    viewModel.setStandardView(view);
    if (onCenterAxes != null) {
      onCenterAxes!();
    } else if (onResetView != null) {
      onResetView!();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLight = viewModel.isLightBackground;
    final currentAzimuth = (viewModel.azimuthDeg % 360.0 + 360.0) % 360.0;
    final currentElevation = viewModel.elevationDeg;

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: isLight ? Colors.white.withValues(alpha: 0.96) : const Color(0xFF1E1E26).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isLight ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isLight ? 0.08 : 0.35),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left vertical drag grip dots (matching SS3)
          _buildDragGrip(isLight),
          const SizedBox(width: 4),

          // 1. Iso View
          _buildViewButton(
            tooltip: 'Iso (Isometric View)',
            isActive: (currentAzimuth - 45.0).abs() < 5.0 && (currentElevation - 35.26).abs() < 5.0,
            painter: _IsoHousePainter(isLight: isLight),
            onTap: () => _selectView(SketchUpStandardView.iso),
            isLight: isLight,
          ),

          // 2. Top View
          _buildViewButton(
            tooltip: 'Top View (Roof)',
            isActive: (currentElevation - 90.0).abs() < 2.0 || (currentElevation - 89.9).abs() < 2.0,
            painter: _TopHousePainter(isLight: isLight),
            onTap: () => _selectView(SketchUpStandardView.top),
            isLight: isLight,
          ),

          // 3. Front View
          _buildViewButton(
            tooltip: 'Front View',
            isActive: currentAzimuth.abs() < 5.0 && currentElevation.abs() < 5.0,
            painter: _FrontHousePainter(isLight: isLight),
            onTap: () => _selectView(SketchUpStandardView.front),
            isLight: isLight,
          ),

          // 4. Right View
          _buildViewButton(
            tooltip: 'Right View',
            isActive: (currentAzimuth - 90.0).abs() < 5.0 && currentElevation.abs() < 5.0,
            painter: _RightHousePainter(isLight: isLight),
            onTap: () => _selectView(SketchUpStandardView.right),
            isLight: isLight,
          ),

          // 5. Back View
          _buildViewButton(
            tooltip: 'Back View',
            isActive: (currentAzimuth - 180.0).abs() < 5.0 && currentElevation.abs() < 5.0,
            painter: _BackHousePainter(isLight: isLight),
            onTap: () => _selectView(SketchUpStandardView.back),
            isLight: isLight,
          ),

          // 6. Left View
          _buildViewButton(
            tooltip: 'Left View',
            isActive: ((currentAzimuth - 270.0).abs() < 5.0 || (currentAzimuth - (-90.0)).abs() < 5.0) && currentElevation.abs() < 5.0,
            painter: _LeftHousePainter(isLight: isLight),
            onTap: () => _selectView(SketchUpStandardView.left),
            isLight: isLight,
          ),

          // 7. Bottom View
          _buildViewButton(
            tooltip: 'Bottom View',
            isActive: (currentElevation - (-89.9)).abs() < 2.0 || (currentElevation - (-90.0)).abs() < 2.0,
            painter: _BottomHousePainter(isLight: isLight),
            onTap: () => _selectView(SketchUpStandardView.bottom),
            isLight: isLight,
          ),
        ],
      ),
    );
  }

  Widget _buildDragGrip(bool isLight) {
    final dotColor = isLight ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: onDragUpdate,
      child: MouseRegion(
        cursor: SystemMouseCursors.move,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 2.2, height: 2.2, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
                  const SizedBox(width: 2),
                  Container(width: 2.2, height: 2.2, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
                ],
              ),
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 2.2, height: 2.2, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
                  const SizedBox(width: 2),
                  Container(width: 2.2, height: 2.2, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
                ],
              ),
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 2.2, height: 2.2, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
                  const SizedBox(width: 2),
                  Container(width: 2.2, height: 2.2, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildViewButton({
    required String tooltip,
    required bool isActive,
    required CustomPainter painter,
    required VoidCallback onTap,
    required bool isLight,
  }) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 32,
          height: 30,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: isActive
                ? (isLight ? const Color(0xFFE0F2FE) : const Color(0xFF0369A1).withValues(alpha: 0.35))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isActive ? const Color(0xFF38BDF8) : Colors.transparent,
              width: 1.0,
            ),
          ),
          child: Center(
            child: CustomPaint(
              size: const Size(22, 22),
              painter: painter,
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// SKETCHUP HOUSE ICON CUSTOM PAINTERS (SS3)
// =============================================================================

Color _strokeColor(bool isLight) => isLight ? const Color(0xFF1E3A5F) : const Color(0xFF93C5FD);

/// 1. Iso View: 3D Isometric house with gable, side wall, pitched roof, chimney
class _IsoHousePainter extends CustomPainter {
  final bool isLight;
  _IsoHousePainter({required this.isLight});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = _strokeColor(isLight)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fill = Paint()
      ..color = _strokeColor(isLight).withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    // Isometric house vertices
    // Left gable face
    final pLeftBottom = Offset(size.width * 0.12, size.height * 0.68);
    final pLeftMid = Offset(size.width * 0.12, size.height * 0.42);
    final pGablePeak = Offset(size.width * 0.32, size.height * 0.25);
    final pCenterBottom = Offset(size.width * 0.38, size.height * 0.88);
    final pCenterMid = Offset(size.width * 0.38, size.height * 0.50);

    // Front gable
    final gablePath = Path()
      ..moveTo(pLeftBottom.dx, pLeftBottom.dy)
      ..lineTo(pCenterBottom.dx, pCenterBottom.dy)
      ..lineTo(pCenterMid.dx, pCenterMid.dy)
      ..lineTo(pGablePeak.dx, pGablePeak.dy)
      ..lineTo(pLeftMid.dx, pLeftMid.dy)
      ..close();
    canvas.drawPath(gablePath, stroke);

    // Window on front gable
    final winRect = Rect.fromCenter(
      center: Offset(size.width * 0.26, size.height * 0.66),
      width: size.width * 0.12,
      height: size.height * 0.14,
    );
    canvas.drawRect(winRect, stroke);

    // Right wall extending in axonometric
    final pRightBottom = Offset(size.width * 0.82, size.height * 0.68);
    final pRightMid = Offset(size.width * 0.82, size.height * 0.35);
    final pRidgeBack = Offset(size.width * 0.76, size.height * 0.14);

    final rightWall = Path()
      ..moveTo(pCenterBottom.dx, pCenterBottom.dy)
      ..lineTo(pRightBottom.dx, pRightBottom.dy)
      ..lineTo(pRightMid.dx, pRightMid.dy)
      ..lineTo(pCenterMid.dx, pCenterMid.dy)
      ..close();
    canvas.drawPath(rightWall, stroke);

    // Roof slope
    final roofSlope = Path()
      ..moveTo(pCenterMid.dx, pCenterMid.dy)
      ..lineTo(pGablePeak.dx, pGablePeak.dy)
      ..lineTo(pRidgeBack.dx, pRidgeBack.dy)
      ..lineTo(pRightMid.dx, pRightMid.dy)
      ..close();
    canvas.drawPath(roofSlope, fill);
    canvas.drawPath(roofSlope, stroke);

    // Chimney on left ridge
    final chimPath = Path()
      ..moveTo(size.width * 0.22, size.height * 0.34)
      ..lineTo(size.width * 0.22, size.height * 0.16)
      ..lineTo(size.width * 0.28, size.height * 0.16)
      ..lineTo(size.width * 0.28, size.height * 0.28)
      ..close();
    canvas.drawPath(chimPath, fill);
    canvas.drawPath(chimPath, stroke);
  }

  @override
  bool shouldRepaint(covariant _IsoHousePainter oldDelegate) => oldDelegate.isLight != isLight;
}

/// 2. Top View: Plan view showing roof rectangle, center ridge line, and chimney tab
class _TopHousePainter extends CustomPainter {
  final bool isLight;
  _TopHousePainter({required this.isLight});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = _strokeColor(isLight)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fill = Paint()
      ..color = _strokeColor(isLight).withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    // Outer roof rectangle
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTRB(size.width * 0.15, size.height * 0.18, size.width * 0.78, size.height * 0.82),
      const Radius.circular(1.5),
    );
    canvas.drawRRect(rect, stroke);

    // Central roof ridge line
    canvas.drawLine(
      Offset(size.width * 0.46, size.height * 0.18),
      Offset(size.width * 0.46, size.height * 0.82),
      stroke,
    );

    // Chimney tab on right
    final chimRect = Rect.fromLTRB(size.width * 0.78, size.height * 0.30, size.width * 0.90, size.height * 0.48);
    canvas.drawRect(chimRect, fill);
    canvas.drawRect(chimRect, stroke);
  }

  @override
  bool shouldRepaint(covariant _TopHousePainter oldDelegate) => oldDelegate.isLight != isLight;
}

/// 3. Front View: Front gable wall with door and chimney on right
class _FrontHousePainter extends CustomPainter {
  final bool isLight;
  _FrontHousePainter({required this.isLight});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = _strokeColor(isLight)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final doorFill = Paint()
      ..color = _strokeColor(isLight)
      ..style = PaintingStyle.fill;

    // House gable wall path
    final housePath = Path()
      ..moveTo(size.width * 0.18, size.height * 0.84)
      ..lineTo(size.width * 0.18, size.height * 0.44)
      ..lineTo(size.width * 0.48, size.height * 0.20)
      ..lineTo(size.width * 0.78, size.height * 0.44)
      ..lineTo(size.width * 0.78, size.height * 0.84)
      ..close();
    canvas.drawPath(housePath, stroke);

    // Chimney on right slope
    final chimPath = Path()
      ..moveTo(size.width * 0.64, size.height * 0.33)
      ..lineTo(size.width * 0.64, size.height * 0.14)
      ..lineTo(size.width * 0.74, size.height * 0.14)
      ..lineTo(size.width * 0.74, size.height * 0.41)
      ..close();
    canvas.drawPath(chimPath, stroke);

    // Door in center bottom
    final doorRect = Rect.fromLTRB(size.width * 0.42, size.height * 0.52, size.width * 0.54, size.height * 0.84);
    canvas.drawRect(doorRect, doorFill);
  }

  @override
  bool shouldRepaint(covariant _FrontHousePainter oldDelegate) => oldDelegate.isLight != isLight;
}

/// 4. Right View: Right side wall rectangle with vertical seam and chimney
class _RightHousePainter extends CustomPainter {
  final bool isLight;
  _RightHousePainter({required this.isLight});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = _strokeColor(isLight)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Side wall rectangle
    final wall = Rect.fromLTRB(size.width * 0.16, size.height * 0.24, size.width * 0.76, size.height * 0.84);
    canvas.drawRect(wall, stroke);

    // Vertical wall panel seam
    canvas.drawLine(
      Offset(size.width * 0.52, size.height * 0.24),
      Offset(size.width * 0.52, size.height * 0.84),
      stroke,
    );

    // Chimney on top right
    final chim = Path()
      ..moveTo(size.width * 0.60, size.height * 0.24)
      ..lineTo(size.width * 0.60, size.height * 0.12)
      ..lineTo(size.width * 0.70, size.height * 0.12)
      ..lineTo(size.width * 0.70, size.height * 0.24);
    canvas.drawPath(chim, stroke);
  }

  @override
  bool shouldRepaint(covariant _RightHousePainter oldDelegate) => oldDelegate.isLight != isLight;
}

/// 5. Back View: Rear wall with square window and chimney on left
class _BackHousePainter extends CustomPainter {
  final bool isLight;
  _BackHousePainter({required this.isLight});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = _strokeColor(isLight)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Chimney on left
    final chim = Path()
      ..moveTo(size.width * 0.40, size.height * 0.16)
      ..lineTo(size.width * 0.40, size.height * 0.26)
      ..lineTo(size.width * 0.50, size.height * 0.26)
      ..lineTo(size.width * 0.50, size.height * 0.16)
      ..close();
    canvas.drawPath(chim, stroke);

    // Rear wall rectangle
    final wall = Rect.fromLTRB(size.width * 0.18, size.height * 0.26, size.width * 0.82, size.height * 0.84);
    canvas.drawRect(wall, stroke);

    // Eaves line
    canvas.drawLine(
      Offset(size.width * 0.18, size.height * 0.38),
      Offset(size.width * 0.82, size.height * 0.38),
      stroke,
    );

    // Square window in lower left
    final win = Rect.fromLTRB(size.width * 0.28, size.height * 0.56, size.width * 0.44, size.height * 0.72);
    canvas.drawRect(win, stroke);
  }

  @override
  bool shouldRepaint(covariant _BackHousePainter oldDelegate) => oldDelegate.isLight != isLight;
}

/// 6. Left View: Left wall with chimney on left
class _LeftHousePainter extends CustomPainter {
  final bool isLight;
  _LeftHousePainter({required this.isLight});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = _strokeColor(isLight)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Left wall with roof slope
    final house = Path()
      ..moveTo(size.width * 0.24, size.height * 0.84)
      ..lineTo(size.width * 0.24, size.height * 0.46)
      ..lineTo(size.width * 0.50, size.height * 0.22)
      ..lineTo(size.width * 0.78, size.height * 0.46)
      ..lineTo(size.width * 0.78, size.height * 0.84)
      ..close();
    canvas.drawPath(house, stroke);

    // Chimney on left
    final chim = Path()
      ..moveTo(size.width * 0.16, size.height * 0.84)
      ..lineTo(size.width * 0.16, size.height * 0.14)
      ..lineTo(size.width * 0.24, size.height * 0.14)
      ..lineTo(size.width * 0.24, size.height * 0.46);
    canvas.drawPath(chim, stroke);
  }

  @override
  bool shouldRepaint(covariant _LeftHousePainter oldDelegate) => oldDelegate.isLight != isLight;
}

/// 7. Bottom View: Inverted plan view
class _BottomHousePainter extends CustomPainter {
  final bool isLight;
  _BottomHousePainter({required this.isLight});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = _strokeColor(isLight)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fill = Paint()
      ..color = _strokeColor(isLight).withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    // Bottom rectangular outline with tab
    final path = Path()
      ..moveTo(size.width * 0.20, size.height * 0.18)
      ..lineTo(size.width * 0.80, size.height * 0.18)
      ..lineTo(size.width * 0.80, size.height * 0.82)
      ..lineTo(size.width * 0.20, size.height * 0.82)
      ..lineTo(size.width * 0.20, size.height * 0.40)
      ..lineTo(size.width * 0.12, size.height * 0.40)
      ..lineTo(size.width * 0.12, size.height * 0.26)
      ..lineTo(size.width * 0.20, size.height * 0.26)
      ..close();

    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _BottomHousePainter oldDelegate) => oldDelegate.isLight != isLight;
}
