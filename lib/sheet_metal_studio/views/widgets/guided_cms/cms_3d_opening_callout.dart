// =============================================================================
// cms_3d_opening_callout.dart
//
// 3D callout widget rendering pinned leader pegs, dimension pills, and port
// identification labels over the 3D folded viewport per
// TRUFOLD_LEGACY_ISOLATION_CLEAN_CMS_ARCHITECTURE.md (Sections 15, 16, 25).
// =============================================================================

import 'package:flutter/material.dart';

import '../../../models/cms/cms_physical_port.dart';

class Cms3DOpeningCallout extends StatelessWidget {
  final CmsPhysicalPort port;
  final Offset anchorScreenPosition;
  final bool isFocused;
  final VoidCallback? onTap;

  const Cms3DOpeningCallout({super.key, required this.port, required this.anchorScreenPosition, this.isFocused = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final accentColor = isFocused ? const Color(0xFF0284C7) : const Color(0xFF059669);

    // Position the badge offset above and slightly centered over the anchor peg
    const badgeWidth = 130.0;
    const badgeHeight = 44.0;
    const pegLeaderLen = 28.0;

    final badgeLeft = anchorScreenPosition.dx - (badgeWidth / 2.0);
    final badgeTop = anchorScreenPosition.dy - badgeHeight - pegLeaderLen;

    return Stack(
      children: [
        // 1. Leader Line & Peg Dot Painter (non-interactive visual annotation)
        IgnorePointer(
          child: CustomPaint(
            size: Size.infinite,
            painter: _CalloutLeaderPainter(
              anchor: anchorScreenPosition,
              badgeBottomCenter: Offset(anchorScreenPosition.dx, badgeTop + badgeHeight),
              color: accentColor,
            ),
          ),
        ),

        // 2. Interactive Badge Card (only intercepts if onTap is provided)
        Positioned(
          left: badgeLeft,
          top: badgeTop,
          child: IgnorePointer(
            ignoring: onTap == null,
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                width: badgeWidth,
                padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8.0),
                  border: Border.all(color: accentColor, width: isFocused ? 2.0 : 1.5),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8.0, offset: const Offset(0, 3))],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8.0,
                      height: 8.0,
                      decoration: BoxDecoration(color: accentColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8.0),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Text(
                                port.id,
                                style: TextStyle(fontSize: 11.0, fontWeight: FontWeight.w800, color: accentColor, letterSpacing: 0.5),
                              ),
                              if (port.role != null && port.role != CmsPortRole.unassigned) ...[
                                const SizedBox(width: 4.0),
                                Text(
                                  '• ${port.role!.displayName}',
                                  style: const TextStyle(fontSize: 9.0, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2.0),
                          Text(
                            '${port.width.toStringAsFixed(1)} × ${port.height.toStringAsFixed(1)} mm',
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A), fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CalloutLeaderPainter extends CustomPainter {
  final Offset anchor;
  final Offset badgeBottomCenter;
  final Color color;

  _CalloutLeaderPainter({required this.anchor, required this.badgeBottomCenter, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final leaderPaint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;

    // Leader line connecting anchor to badge
    canvas.drawLine(anchor, badgeBottomCenter, leaderPaint);

    // Outer anchor peg ring
    final pegOuterPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(anchor, 4.0, pegOuterPaint);

    // Inner white peg center
    final pegInnerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(anchor, 2.0, pegInnerPaint);
  }

  @override
  bool shouldRepaint(covariant _CalloutLeaderPainter oldDelegate) {
    return oldDelegate.anchor != anchor || oldDelegate.badgeBottomCenter != badgeBottomCenter || oldDelegate.color != color;
  }
}
