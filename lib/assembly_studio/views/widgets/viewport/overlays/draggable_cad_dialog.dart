import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Reusable draggable floating dialog wrapper for CAD overlays (Extrude, Sketch, etc.)
/// Prevents dialogs from blocking the 3D model being edited (Section 5).
class DraggableCadDialog extends StatefulWidget {
  final Widget child;
  final Offset initialOffset;
  final double width;

  const DraggableCadDialog({
    super.key,
    required this.child,
    this.initialOffset = const Offset(24, 72),
    this.width = 290,
  });

  @override
  State<DraggableCadDialog> createState() => _DraggableCadDialogState();
}

class _DraggableCadDialogState extends State<DraggableCadDialog> {
  late Offset _offset;

  @override
  void initState() {
    super.initState();
    _offset = widget.initialOffset;
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    return Positioned(
      left: _offset.dx.clamp(8.0, math.max(8.0, screenSize.width - widget.width - 8.0)),
      top: _offset.dy.clamp(8.0, math.max(8.0, screenSize.height - 260.0)),
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onPanUpdate: (DragUpdateDetails details) {
          setState(() {
            _offset += details.delta;
          });
        },
        child: Material(
          color: Colors.transparent,
          elevation: 8,
          child: widget.child,
        ),
      ),
    );
  }
}
