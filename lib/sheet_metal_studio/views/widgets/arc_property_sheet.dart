// =============================================================================
// arc_property_sheet.dart
//
// Floating On-Canvas Property Inspector for selected CAD Arc Entities (CadArc2D).
// Allows rapid modification of Center (X, Y), Radius, Start & End Angles,
// Layer classification, Reverse Direction, and Deletion.
// =============================================================================

import 'package:flutter/material.dart';

import '../../models/cad_primitives.dart';
import '../../viewmodels/sheet_metal_studio_viewmodel.dart';

class ArcPropertySheet extends StatefulWidget {
  final SheetMetalStudioViewModel viewModel;
  final CadArc2D arc;
  final bool isCollapsed;
  final VoidCallback? onToggleCollapse;
  final VoidCallback? onClose;
  final GestureDragStartCallback? onDragStartHeader;
  final GestureDragUpdateCallback? onDragHeader;

  const ArcPropertySheet({
    super.key,
    required this.viewModel,
    required this.arc,
    this.isCollapsed = false,
    this.onToggleCollapse,
    this.onClose,
    this.onDragStartHeader,
    this.onDragHeader,
  });

  @override
  State<ArcPropertySheet> createState() => _ArcPropertySheetState();
}

class _ArcPropertySheetState extends State<ArcPropertySheet> {
  late TextEditingController _cxCtrl;
  late TextEditingController _cyCtrl;
  late TextEditingController _radiusCtrl;
  late TextEditingController _startAngleCtrl;
  late TextEditingController _endAngleCtrl;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  void _initControllers() {
    _cxCtrl = TextEditingController(text: widget.arc.center.x.toStringAsFixed(2));
    _cyCtrl = TextEditingController(text: widget.arc.center.y.toStringAsFixed(2));
    _radiusCtrl = TextEditingController(text: widget.arc.radius.toStringAsFixed(2));
    _startAngleCtrl = TextEditingController(text: widget.arc.startAngleDeg.toStringAsFixed(1));
    _endAngleCtrl = TextEditingController(text: widget.arc.endAngleDeg.toStringAsFixed(1));
  }

  @override
  void didUpdateWidget(covariant ArcPropertySheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.arc.id != widget.arc.id ||
        (oldWidget.arc.center.x - widget.arc.center.x).abs() > 1e-4 ||
        (oldWidget.arc.center.y - widget.arc.center.y).abs() > 1e-4 ||
        (oldWidget.arc.radius - widget.arc.radius).abs() > 1e-4 ||
        (oldWidget.arc.startAngleDeg - widget.arc.startAngleDeg).abs() > 1e-4 ||
        (oldWidget.arc.endAngleDeg - widget.arc.endAngleDeg).abs() > 1e-4) {
      _initControllers();
    }
  }

  @override
  void dispose() {
    _cxCtrl.dispose();
    _cyCtrl.dispose();
    _radiusCtrl.dispose();
    _startAngleCtrl.dispose();
    _endAngleCtrl.dispose();
    super.dispose();
  }

  void _applyChanges() {
    final cx = double.tryParse(_cxCtrl.text) ?? widget.arc.center.x;
    final cy = double.tryParse(_cyCtrl.text) ?? widget.arc.center.y;
    final r = (double.tryParse(_radiusCtrl.text) ?? widget.arc.radius).clamp(0.5, 5000.0);
    final sa = double.tryParse(_startAngleCtrl.text) ?? widget.arc.startAngleDeg;
    final ea = double.tryParse(_endAngleCtrl.text) ?? widget.arc.endAngleDeg;

    final updated = CadArc2D(
      id: widget.arc.id,
      center: CadPoint2D(cx, cy),
      radius: r,
      startAngleDeg: sa,
      endAngleDeg: ea,
      layer: widget.arc.layer,
      isBoundary: widget.arc.isBoundary,
    );

    widget.viewModel.updateArc(updated);
  }

  void _reverseArc() {
    final reversed = CadArc2D(
      id: widget.arc.id,
      center: widget.arc.center,
      radius: widget.arc.radius,
      startAngleDeg: widget.arc.endAngleDeg,
      endAngleDeg: widget.arc.startAngleDeg,
      layer: widget.arc.layer,
      isBoundary: widget.arc.isBoundary,
    );
    widget.viewModel.updateArc(reversed);
  }

  @override
  Widget build(BuildContext context) {
    const themeColor = Color(0xFF0284C7); // Sky CAD blue for Arc entities

    return Container(
      width: 260.0,
      padding: const EdgeInsets.all(10.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(
          color: themeColor.withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16.0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          GestureDetector(
            onPanStart: widget.onDragStartHeader,
            onPanUpdate: widget.onDragHeader,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                const Icon(Icons.drag_indicator, size: 14, color: Color(0xFF94A3B8)),
                const SizedBox(width: 4),
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: themeColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${widget.arc.id} (CAD ARC)',
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InkWell(
                  onTap: widget.onToggleCollapse,
                  child: Icon(
                    widget.isCollapsed ? Icons.expand_more : Icons.expand_less,
                    size: 16,
                    color: const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: widget.onClose,
                  child: const Icon(Icons.close, size: 14, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),

          if (!widget.isCollapsed) ...[
            const Divider(height: 14, color: Color(0xFFE2E8F0)),

            // Type Badge & Length
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: widget.arc.isBoundary
                        ? const Color(0xFFEFF6FF)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: widget.arc.isBoundary
                          ? const Color(0xFF93C5FD)
                          : const Color(0xFFCBD5E1),
                    ),
                  ),
                  child: Text(
                    widget.arc.isBoundary ? 'BOUNDARY ARC' : 'CUT ARC',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      color: widget.arc.isBoundary
                          ? const Color(0xFF1D4ED8)
                          : const Color(0xFF475569),
                    ),
                  ),
                ),
                Text(
                  'L: ${widget.arc.arcLength.toStringAsFixed(1)} mm',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Center Coordinates
            Row(
              children: [
                Expanded(
                  child: _numInput(
                    label: 'Center X',
                    controller: _cxCtrl,
                    suffix: 'mm',
                    onSubmitted: _applyChanges,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _numInput(
                    label: 'Center Y',
                    controller: _cyCtrl,
                    suffix: 'mm',
                    onSubmitted: _applyChanges,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Radius
            _numInput(
              label: 'Radius (R)',
              controller: _radiusCtrl,
              suffix: 'mm',
              onSubmitted: _applyChanges,
            ),
            const SizedBox(height: 6),

            // Start & End Angles
            Row(
              children: [
                Expanded(
                  child: _numInput(
                    label: 'Start ∠',
                    controller: _startAngleCtrl,
                    suffix: '°',
                    onSubmitted: _applyChanges,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _numInput(
                    label: 'End ∠',
                    controller: _endAngleCtrl,
                    suffix: '°',
                    onSubmitted: _applyChanges,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Computed Sweep
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Sweep Angle:', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                  Text(
                    '${widget.arc.sweepAngleDeg.toStringAsFixed(1)}°',
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                    onPressed: _reverseArc,
                    icon: const Icon(Icons.swap_horiz, size: 14, color: Color(0xFF475569)),
                    label: const Text('Reverse', style: TextStyle(fontSize: 10, color: Color(0xFF334155))),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      side: const BorderSide(color: Color(0xFFFECACA)),
                      backgroundColor: const Color(0xFFFEF2F2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                    onPressed: () {
                      widget.viewModel.deleteArc(widget.arc.id);
                    },
                    icon: const Icon(Icons.delete_outline, size: 14, color: Color(0xFFDC2626)),
                    label: const Text('Delete', style: TextStyle(fontSize: 10, color: Color(0xFFDC2626))),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _numInput({
    required String label,
    required TextEditingController controller,
    required String suffix,
    required VoidCallback onSubmitted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 2),
        SizedBox(
          height: 28,
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              suffixText: suffix,
              suffixStyle: const TextStyle(fontSize: 9.5, color: Color(0xFF94A3B8)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: Color(0xFF0284C7), width: 1.5),
              ),
            ),
            onSubmitted: (_) => onSubmitted(),
          ),
        ),
      ],
    );
  }
}
