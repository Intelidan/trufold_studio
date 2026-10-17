import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../sheet_metal_studio/engine/constraints/expression_parser_engine.dart';
import '../../../../viewmodels/assembly_studio_viewmodel.dart';

/// Onshape Inline Floating Dimension Popover (matches image_31d0a3.png) +
/// Compact Contextual Sketch Quick-Action Pill (replaces the clunky CIRCLE PARAMETERS modal).
class AssemblySketchParameterPanel extends StatefulWidget {
  final AssemblyStudioViewModel viewModel;
  final VoidCallback? onRebuildModel;

  const AssemblySketchParameterPanel({
    super.key,
    required this.viewModel,
    this.onRebuildModel,
  });

  @override
  State<AssemblySketchParameterPanel> createState() => _AssemblySketchParameterPanelState();
}

class _AssemblySketchParameterPanelState extends State<AssemblySketchParameterPanel> {
  late TextEditingController _valueController;
  late TextEditingController _tolController;
  final FocusNode _focusNode = FocusNode();
  String? _lastTagKey;
  bool _showTolerance = false;

  @override
  void initState() {
    super.initState();
    _valueController = TextEditingController();
    _tolController = TextEditingController(text: '0.1');
    _syncFromActiveDimension();
  }

  @override
  void didUpdateWidget(covariant AssemblySketchParameterPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFromActiveDimension();
  }

  void _syncFromActiveDimension() {
    final hit = widget.viewModel.activeEditingDimensionHit;
    if (hit != null && hit.tagKey != _lastTagKey) {
      _lastTagKey = hit.tagKey;
      final formatted = (hit.currentValue - hit.currentValue.roundToDouble()).abs() < 0.05
          ? hit.currentValue.round().toString()
          : hit.currentValue.toStringAsFixed(1);
      _valueController.text = '$formatted ${hit.unitSuffix}';
      _valueController.selection = TextSelection(baseOffset: 0, extentOffset: formatted.length);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    } else if (hit == null) {
      _lastTagKey = null;
    }
  }

  void _commitDimension() {
    final vm = widget.viewModel;
    final hit = vm.activeEditingDimensionHit;
    if (hit == null) return;

    final raw = _valueController.text
        .replaceAll('mm', '')
        .replaceAll('deg', '')
        .replaceAll('°', '')
        .replaceAll('Ø', '')
        .replaceAll('R', '')
        .trim();

    double? parsed = double.tryParse(raw);
    String? expr;
    if (parsed == null && raw.isNotEmpty) {
      try {
        parsed = ExpressionParserEngine.evaluate(raw, const {});
        expr = raw;
      } catch (_) {}
    }

    if (parsed != null && parsed > 0) {
      final double? tol = _showTolerance ? double.tryParse(_tolController.text.trim()) : null;
      vm.commitInlineSketchDimension(
        hit: hit,
        newValue: parsed,
        expression: expr,
        tolerancePlusMinus: tol,
      );
      widget.onRebuildModel?.call();
    } else {
      vm.closeInlineSketchDimensionEditor();
    }
  }

  @override
  void dispose() {
    _valueController.dispose();
    _tolController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final hit = vm.activeEditingDimensionHit;

    // 1. ONSHAPE INLINE FLOATING DIMENSION POPOVER (image_31d0a3.png)
    if (hit != null) {
      return Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: const Color(0xFF94A3B8), width: 1.0),
            boxShadow: const [
              BoxShadow(color: Color(0x29000000), blurRadius: 10, offset: Offset(0, 3)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Dimension Value Input Box (e.g. "60 mm")
                  Container(
                    width: 104,
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: const Color(0xFF0284C7), width: 1.6),
                    ),
                    child: KeyboardListener(
                      focusNode: FocusNode(),
                      onKeyEvent: (event) {
                        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
                          vm.closeInlineSketchDimensionEditor();
                        }
                      },
                      child: TextField(
                        controller: _valueController,
                        focusNode: _focusNode,
                        autofocus: true,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 5),
                        ),
                        onSubmitted: (_) => _commitDimension(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Onshape '±' Tolerance Button (image_31d0a3.png)
                  Tooltip(
                    message: 'Toggle ± Tolerance',
                    child: InkWell(
                      onTap: () => setState(() => _showTolerance = !_showTolerance),
                      borderRadius: BorderRadius.circular(3),
                      child: Container(
                        width: 26,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _showTolerance ? const Color(0xFFE0F2FE) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: _showTolerance ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1),
                          ),
                        ),
                        child: const Text(
                          '±',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Green Check (Accept / Enter)
                  Tooltip(
                    message: 'Accept dimension (Enter)',
                    child: InkWell(
                      onTap: _commitDimension,
                      borderRadius: BorderRadius.circular(3),
                      child: Container(
                        width: 24,
                        height: 28,
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Icon(Icons.check, size: 15, color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(width: 3),
                  // Cancel (Esc)
                  Tooltip(
                    message: 'Cancel (Esc)',
                    child: InkWell(
                      onTap: vm.closeInlineSketchDimensionEditor,
                      borderRadius: BorderRadius.circular(3),
                      child: Container(
                        width: 24,
                        height: 28,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: const Icon(Icons.close, size: 14, color: Color(0xFF64748B)),
                      ),
                    ),
                  ),
                ],
              ),
              if (_showTolerance) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Tol ±',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 72,
                      height: 24,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: TextField(
                        controller: _tolController,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 4),
                        ),
                        onSubmitted: (_) => _commitDimension(),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    }

    // 2. COMPACT CONTEXTUAL SKETCH ACTION BAR (When an entity is selected, no bulky modal!)
    final entity = vm.selectedSketchEntity;
    if (entity == null) return const SizedBox.shrink();

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFCBD5E1)),
          boxShadow: const [BoxShadow(color: Color(0x18000000), blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildCompactActionChip(
              icon: Icons.power_input_rounded,
              label: entity.isConstruction ? 'Solid (Q)' : 'Construction (Q)',
              isActive: entity.isConstruction,
              onTap: vm.toggleSketchConstructionMode,
            ),
            const SizedBox(width: 4),
            _buildCompactActionChip(
              icon: Icons.straighten_rounded,
              label: 'Dimension (D)',
              isActive: vm.activeSketchTool == 'dimension',
              onTap: () {
                final hitMatch = vm.sketchDimensionHitRects
                    .where((h) => h.primaryEntityId == entity.id)
                    .firstOrNull;
                if (hitMatch != null) {
                  vm.openInlineSketchDimensionEditor(hitMatch);
                } else {
                  vm.setActiveSketchTool('dimension');
                }
              },
            ),
            const SizedBox(width: 4),
            _buildCompactActionChip(
              icon: Icons.layers_rounded,
              label: 'Extrude (E)',
              isActive: vm.isExtrudeMode,
              onTap: vm.toggleExtrudeMode,
            ),
            const SizedBox(width: 4),
            IconButton(
               visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
              tooltip: 'Delete Sketch Entity (Del)',
              icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFDC2626)),
              onPressed: () {
                vm.deleteSelectedSketchEntity();
                widget.onRebuildModel?.call();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactActionChip({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFE0F2FE) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: isActive ? const Color(0xFF0284C7) : const Color(0xFFE2E8F0)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: isActive ? const Color(0xFF0284C7) : const Color(0xFF475569)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: isActive ? const Color(0xFF0284C7) : const Color(0xFF334155),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
