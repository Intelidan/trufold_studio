// =============================================================================
// cms_channel_topology_pictograph.dart
//
// Dynamic Topological Pictograph & Metrics Dashboard for DSF Fitting Inspector.
// Visualizes channel cross-section profile (W × H × Flange × Thk) and flow topology
// (Port 1 Inlet -> Miter/Bend Core -> Port 2 Outlet) with rich CAD aesthetics.
// =============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/cms/cms_product_contract.dart';
import '../../models/cms/cms_physical_port.dart';

class CmsChannelTopologyPictograph extends StatelessWidget {
  final CmsProductContract contract;
  final List<CmsPhysicalPort> ports;
  final double sheetThickness;
  final double flangeMm;
  final int bendCount;
  final int? wallCount;
  final int? flangeCount;
  final int couplerCount;
  final VoidCallback? onLaunchTeachScaling;

  const CmsChannelTopologyPictograph({
    super.key,
    required this.contract,
    required this.ports,
    required this.sheetThickness,
    required this.flangeMm,
    this.bendCount = 3,
    this.wallCount,
    this.flangeCount,
    this.couplerCount = 8,
    this.onLaunchTeachScaling,
  });

  @override
  Widget build(BuildContext context) {
    final port1 = ports.isNotEmpty ? ports.first : null;
    final port2 = ports.length > 1 ? ports[1] : null;

    final double width1 = toNominalSize(port1?.width ?? 98.0);
    final double height1 = toNominalSize(port1?.height ?? 92.0);
    final double width2 = toNominalSize(port2?.width ?? width1);
    final double height2 = toNominalSize(port2?.height ?? height1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Stage 7 Complete Banner with Action to Launch Teach Scaling
        _buildTeachScalingLaunchBanner(context),
        const SizedBox(height: 10),

        // 2. Dual Pictographs Card: Cross-Section & Flow Topology
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFBAE6FD), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0284C7).withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Icon(Icons.schema_outlined, size: 16, color: Color(0xFF0284C7)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CHANNEL TOPOLOGY & FLOW SCHEMATIC (${contract.displayName})',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                            letterSpacing: 0.4,
                          ),
                        ),
                        Text(
                          'Verified 3D channel profile with normal vector orientations and kinematic zones.',
                          style: TextStyle(fontSize: 10, color: const Color(0xFF475569)),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF10B981)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, size: 12, color: Color(0xFF059669)),
                        SizedBox(width: 4),
                        Text(
                          'Canonical 2D Linked',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Side-by-Side Visual Diagrams
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Diagram A: U-Channel Cross Section Profile
                  Expanded(
                    flex: 5,
                    child: Container(
                      height: 145,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.crop_free, size: 12, color: Color(0xFF0284C7)),
                              SizedBox(width: 4),
                              Text(
                                'Mouth Cross-Section',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                              ),
                            ],
                          ),
                          Expanded(
                            child: CustomPaint(
                              size: Size.infinite,
                              painter: _ChannelCrossSectionPainter(
                                width: width1,
                                height: height1,
                                flangeMm: flangeMm,
                                sheetThickness: sheetThickness,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Diagram B: Flow Topology Plan Schematic
                  Expanded(
                    flex: 6,
                    child: Container(
                      height: 145,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.alt_route, size: 12, color: Color(0xFF0D9488)),
                              SizedBox(width: 4),
                              Text(
                                'Kinematic Fitting Flow Layout',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                              ),
                            ],
                          ),
                          Expanded(
                            child: CustomPaint(
                              size: Size.infinite,
                              painter: _ChannelFlowTopologyPainter(
                                contract: contract,
                                port1: port1,
                                port2: port2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // 3. Topological Feature Matrix Chips & Ratio Bar
              _buildTopologicalFeatureMatrix(width1, height1, width2, height2),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTeachScalingLaunchBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF0FDF4), Color(0xFFE0F2FE)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.4), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF059669).withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF059669).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.verified, color: Color(0xFF059669), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  children: [
                    const Text(
                      'Stage 7: CMS Template Complete & Verified',
                      style: TextStyle(
                        color: Color(0xFF065F46),
                        fontSize: 12.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0F2FE),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFF0284C7)),
                      ),
                      child: const Text(
                        'Ready for Scaling',
                        style: TextStyle(color: Color(0xFF0284C7), fontSize: 9.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'All terminal mouths, bend fold angles, and coupler slots are locked. You can now teach parametric scaling or exit.',
                  style: const TextStyle(color: Color(0xFF334155), fontSize: 10.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: onLaunchTeachScaling,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
              foregroundColor: Colors.white,
              elevation: 2,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
            ),
            icon: const Icon(Icons.tune, size: 15),
            label: const Text(
              'Teach Scaling (Phase 2) →',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopologicalFeatureMatrix(double w1, double h1, double w2, double h2) {
    final effectiveWalls = wallCount ?? (bendCount > 4 ? bendCount ~/ 2 : bendCount);
    final effectiveFlanges = flangeCount ?? (bendCount > 4 ? bendCount ~/ 2 : bendCount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _buildFeatureChip(
              icon: Icons.layers_outlined,
              title: 'Floor Web',
              subtitle: '1 Base (Stretches on Bend Axis)',
              color: const Color(0xFF0284C7),
            ),
            const SizedBox(width: 6),
            _buildFeatureChip(
              icon: Icons.view_sidebar_outlined,
              title: 'Sidewalls',
              subtitle: '$effectiveWalls Walls (Rigid Shift)',
              color: const Color(0xFF0D9488),
            ),
            const SizedBox(width: 6),
            _buildFeatureChip(
              icon: Icons.border_top_outlined,
              title: 'Flanges',
              subtitle: '$effectiveFlanges Flanges (${flangeMm.toStringAsFixed(0)}mm locked)',
              color: const Color(0xFF7C3AED),
            ),
            const SizedBox(width: 6),
            _buildFeatureChip(
              icon: Icons.grid_view_outlined,
              title: 'Coupler Slots',
              subtitle: '$couplerCount Slots (Rigid Pinned)',
              color: const Color(0xFFD97706),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Dimensional Proportion Metrics Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.straighten, size: 13, color: Color(0xFF64748B)),
                  const SizedBox(width: 5),
                  Text(
                    'Port 1: ${w1.toStringAsFixed(0)} × ${h1.toStringAsFixed(0)} mm',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF334155), fontFamily: 'monospace'),
                  ),
                ],
              ),
              Text(
                'Port 2: ${w2.toStringAsFixed(0)} × ${h2.toStringAsFixed(0)} mm',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF334155), fontFamily: 'monospace'),
              ),
              Text(
                'Ratio: ${(w1 / (h1 > 0 ? h1 : 1)).toStringAsFixed(2)}:1',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureChip({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: color),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 8.5, color: Color(0xFF475569)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// CustomPainter that renders a technical CAD cross-section of the open channel profile
class _ChannelCrossSectionPainter extends CustomPainter {
  final double width;
  final double height;
  final double flangeMm;
  final double sheetThickness;

  _ChannelCrossSectionPainter({
    required this.width,
    required this.height,
    required this.flangeMm,
    required this.sheetThickness,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Draw grid background
    final gridPaint = Paint()
      ..color = const Color(0xFFF1F5F9)
      ..strokeWidth = 1.0;
    for (double x = 0; x < w; x += 16) {
      canvas.drawLine(Offset(x, 0), Offset(x, h), gridPaint);
    }
    for (double y = 0; y < h; y += 16) {
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }

    // Geometry layout margins
    final leftX = 32.0;
    final rightX = w - 32.0;
    final bottomY = h - 26.0;
    final topY = 28.0;
    final flangeW = 16.0;

    // Channel Path (U-channel with return flanges)
    final profilePath = Path()
      ..moveTo(leftX - flangeW, topY)
      ..lineTo(leftX, topY)
      ..lineTo(leftX, bottomY)
      ..lineTo(rightX, bottomY)
      ..lineTo(rightX, topY)
      ..lineTo(rightX + flangeW, topY);

    // Channel fill (soft cyan)
    final fillPath = Path.from(profilePath)
      ..lineTo(rightX + flangeW, bottomY + 4)
      ..lineTo(leftX - flangeW, bottomY + 4)
      ..close();
    final fillPaint = Paint()
      ..color = const Color(0xFF0284C7).withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    // Metal profile stroke
    final strokePaint = Paint()
      ..color = const Color(0xFF0284C7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(profilePath, strokePaint);

    // Bend radii dots
    final bendDotPaint = Paint()..color = const Color(0xFF0D9488);
    canvas.drawCircle(Offset(leftX, bottomY), 2.5, bendDotPaint);
    canvas.drawCircle(Offset(rightX, bottomY), 2.5, bendDotPaint);
    canvas.drawCircle(Offset(leftX, topY), 2.0, bendDotPaint);
    canvas.drawCircle(Offset(rightX, topY), 2.0, bendDotPaint);

    // Dimension lines
    final dimPaint = Paint()
      ..color = const Color(0xFF64748B)
      ..strokeWidth = 1.0;

    // Horizontal dimension: Width (W)
    final dimY = bottomY + 14.0;
    canvas.drawLine(Offset(leftX, dimY), Offset(rightX, dimY), dimPaint);
    canvas.drawLine(Offset(leftX, dimY - 3), Offset(leftX, dimY + 3), dimPaint);
    canvas.drawLine(Offset(rightX, dimY - 3), Offset(rightX, dimY + 3), dimPaint);

    // Vertical dimension: Height (H)
    final dimX = leftX - flangeW - 8.0;
    canvas.drawLine(Offset(dimX, topY), Offset(dimX, bottomY), dimPaint);
    canvas.drawLine(Offset(dimX - 3, topY), Offset(dimX + 3, topY), dimPaint);
    canvas.drawLine(Offset(dimX - 3, bottomY), Offset(dimX + 3, bottomY), dimPaint);

    // Text Painter helper
    void drawText(String text, Offset pos, {Color color = const Color(0xFF334155), bool isBold = false}) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: 9.0,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }

    // Dimension labels
    drawText('W: ${width.toStringAsFixed(0)}mm', Offset((leftX + rightX) / 2, dimY + 6), color: const Color(0xFF0284C7), isBold: true);
    drawText('H: ${height.toStringAsFixed(0)}mm', Offset(dimX - 2, (topY + bottomY) / 2), color: const Color(0xFF0D9488), isBold: true);
    drawText('F:${flangeMm.toStringAsFixed(0)}', Offset(rightX + flangeW / 2, topY - 8), color: const Color(0xFF7C3AED));
    drawText('T:${sheetThickness.toStringAsFixed(1)}', Offset((leftX + rightX) / 2, (topY + bottomY) / 2), color: const Color(0xFF94A3B8));
  }

  @override
  bool shouldRepaint(covariant _ChannelCrossSectionPainter oldDelegate) {
    return oldDelegate.width != width ||
        oldDelegate.height != height ||
        oldDelegate.flangeMm != flangeMm ||
        oldDelegate.sheetThickness != sheetThickness;
  }
}

/// CustomPainter that renders a clean planar flow topological schematic of the fitting
class _ChannelFlowTopologyPainter extends CustomPainter {
  final CmsProductContract contract;
  final CmsPhysicalPort? port1;
  final CmsPhysicalPort? port2;

  _ChannelFlowTopologyPainter({
    required this.contract,
    this.port1,
    this.port2,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final cx = w * 0.48;
    final cy = h * 0.52;

    final bgPaint = Paint()..color = const Color(0xFFFAFAFA);
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), bgPaint);

    final isBend45 = contract == CmsProductContract.bend45;
    final isBend90 = contract == CmsProductContract.bend90;
    final isTee = contract == CmsProductContract.equalTee || contract == CmsProductContract.unequalTee;

    final path = Path();
    final armW = 28.0;

    if (isBend45) {
      // 45 degree miter layout
      path.moveTo(cx - 55, cy + 35);
      path.lineTo(cx - 55 + armW, cy + 35);
      path.lineTo(cx + 8, cy - 2);
      path.lineTo(cx + 42, cy - 36);
      path.lineTo(cx + 42 - armW * 0.707, cy - 36 - armW * 0.707);
      path.lineTo(cx - 15, cy - 8);
      path.close();
    } else if (isBend90) {
      // 90 degree elbow layout
      path.moveTo(cx - 45, cy + 35);
      path.lineTo(cx - 45 + armW, cy + 35);
      path.lineTo(cx - 45 + armW, cy - 10);
      path.lineTo(cx + 40, cy - 10);
      path.lineTo(cx + 40, cy - 10 - armW);
      path.lineTo(cx - 45, cy - 10 - armW);
      path.close();
    } else if (isTee) {
      // Tee junction layout
      path.moveTo(cx - 50, cy + 10);
      path.lineTo(cx + 50, cy + 10);
      path.lineTo(cx + 50, cy - 14);
      path.lineTo(cx + 14, cy - 14);
      path.lineTo(cx + 14, cy - 42);
      path.lineTo(cx - 14, cy - 42);
      path.lineTo(cx - 14, cy - 14);
      path.lineTo(cx - 50, cy - 14);
      path.close();
    } else {
      // Straight channel layout
      path.moveTo(cx - 55, cy + armW / 2);
      path.lineTo(cx + 55, cy + armW / 2);
      path.lineTo(cx + 55, cy - armW / 2);
      path.lineTo(cx - 55, cy - armW / 2);
      path.close();
    }

    // Fill channel plan
    final fillPaint = Paint()
      ..color = const Color(0xFFE2E8F0).withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    final strokePaint = Paint()
      ..color = const Color(0xFF94A3B8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(path, strokePaint);

    // Miter bend line(s)
    final bendLinePaint = Paint()
      ..color = const Color(0xFF6366F1)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    if (isBend45) {
      canvas.drawLine(Offset(cx - 27, cy + 35), Offset(cx + 25, cy - 19), bendLinePaint);
    }

    // Flow Arrows
    final arrowPaint = Paint()
      ..color = const Color(0xFF0284C7)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    if (isBend45) {
      // Flow from Port 1 to Port 2
      _drawArrow(canvas, Offset(cx - 42, cy + 45), Offset(cx - 42, cy + 20), arrowPaint);
      _drawArrow(canvas, Offset(cx, cy + 10), Offset(cx + 25, cy - 15), arrowPaint);
    } else {
      _drawArrow(canvas, Offset(cx - 30, cy), Offset(cx + 30, cy), arrowPaint);
    }

    // Port Badges
    _drawPortMarker(canvas, Offset(cx - 42, cy + 42), 'PORT 1 (INLET)', const Color(0xFF0284C7));
    if (isBend45) {
      _drawPortMarker(canvas, Offset(cx + 35, cy - 42), 'PORT 2 (OUTLET)', const Color(0xFF0D9488));
    } else {
      _drawPortMarker(canvas, Offset(cx + 42, cy), 'PORT 2 (OUTLET)', const Color(0xFF0D9488));
    }
  }

  void _drawArrow(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    canvas.drawLine(p1, p2, paint);
    final angle = math.atan2(p2.dy - p1.dy, p2.dx - p1.dx);
    const arrowLen = 6.0;
    const arrowAngle = 25.0 * math.pi / 180.0;

    final pLeft = Offset(
      p2.dx - arrowLen * math.cos(angle - arrowAngle),
      p2.dy - arrowLen * math.sin(angle - arrowAngle),
    );
    final pRight = Offset(
      p2.dx - arrowLen * math.cos(angle + arrowAngle),
      p2.dy - arrowLen * math.sin(angle + arrowAngle),
    );

    final headPath = Path()
      ..moveTo(p2.dx, p2.dy)
      ..lineTo(pLeft.dx, pLeft.dy)
      ..lineTo(pRight.dx, pRight.dy)
      ..close();
    final headPaint = Paint()
      ..color = paint.color
      ..style = PaintingStyle.fill;
    canvas.drawPath(headPath, headPaint);
  }

  void _drawPortMarker(Canvas canvas, Offset pos, String label, Color color) {
    final bgPaint = Paint()..color = color;
    canvas.drawCircle(pos, 4.0, bgPaint);

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: 8.0,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.white.withValues(alpha: 0.85),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos + const Offset(6, -5));
  }

  @override
  bool shouldRepaint(covariant _ChannelFlowTopologyPainter oldDelegate) {
    return oldDelegate.contract != contract ||
        oldDelegate.port1 != port1 ||
        oldDelegate.port2 != port2;
  }
}
