// =============================================================================
// cad_number_spinner.dart
//
// Compact CAD Number Spinner with [-] [+] stepper buttons and direct numeric
// keyboard editing. Clean industrial look matching TruFold Studio light theme.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CadNumberSpinner extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;
  final double step;
  final double min;
  final double max;
  final int decimals;
  final String? suffix;
  final String? label;
  final double? width;
  final bool enabled;

  const CadNumberSpinner({
    super.key,
    required this.value,
    required this.onChanged,
    this.step = 1.0,
    this.min = -999999.0,
    this.max = 999999.0,
    this.decimals = 1,
    this.suffix,
    this.label,
    this.width,
    this.enabled = true,
  });

  @override
  State<CadNumberSpinner> createState() => _CadNumberSpinnerState();
}

class _CadNumberSpinnerState extends State<CadNumberSpinner> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _formatValue(widget.value));
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant CadNumberSpinner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEditing && (oldWidget.value != widget.value || oldWidget.decimals != widget.decimals)) {
      final formatted = _formatValue(widget.value);
      if (_controller.text != formatted) {
        _controller.text = formatted;
      }
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      _isEditing = true;
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    } else {
      _isEditing = false;
      _submitText(_controller.text);
    }
  }

  String _formatValue(double val) {
    if (widget.decimals <= 0) {
      return val.round().toString();
    }
    return val.toStringAsFixed(widget.decimals);
  }

  void _submitText(String text) {
    final parsed = double.tryParse(text.trim());
    if (parsed != null) {
      final clamped = parsed.clamp(widget.min, widget.max);
      widget.onChanged(clamped);
      _controller.text = _formatValue(clamped);
    } else {
      _controller.text = _formatValue(widget.value);
    }
  }

  void _increment() {
    if (!widget.enabled) return;
    final next = (widget.value + widget.step).clamp(widget.min, widget.max);
    widget.onChanged(next);
  }

  void _decrement() {
    if (!widget.enabled) return;
    final next = (widget.value - widget.step).clamp(widget.min, widget.max);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final canDec = widget.enabled && widget.value - widget.step >= widget.min - 1e-6;
    final canInc = widget.enabled && widget.value + widget.step <= widget.max + 1e-6;

    final content = Container(
      height: 28,
      width: widget.width,
      decoration: BoxDecoration(
        color: widget.enabled ? Colors.white : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(4.0),
        border: Border.all(
          color: _focusNode.hasFocus
              ? const Color(0xFF0284C7)
              : const Color(0xFFCBD5E1),
          width: _focusNode.hasFocus ? 1.2 : 0.9,
        ),
      ),
      child: Row(
        mainAxisSize: widget.width != null ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Decrement button
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: canDec ? _decrement : null,
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(3)),
              child: Container(
                width: 22,
                alignment: Alignment.center,
                color: canDec ? const Color(0xFFF8FAFC) : Colors.transparent,
                child: Icon(
                  Icons.remove,
                  size: 13,
                  color: canDec ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1, color: Color(0xFFE2E8F0)),

          // Numeric TextField
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              enabled: widget.enabled,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*')),
              ],
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: widget.enabled ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                border: InputBorder.none,
              ),
              onSubmitted: (val) {
                _submitText(val);
                _focusNode.unfocus();
              },
            ),
          ),

          if (widget.suffix != null) ...[
            Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                widget.suffix!,
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF64748B),
                ),
              ),
            ),
          ],

          const VerticalDivider(width: 1, thickness: 1, color: Color(0xFFE2E8F0)),
          // Increment button
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: canInc ? _increment : null,
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(3)),
              child: Container(
                width: 22,
                alignment: Alignment.center,
                color: canInc ? const Color(0xFFF8FAFC) : Colors.transparent,
                child: Icon(
                  Icons.add,
                  size: 13,
                  color: canInc ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (widget.label != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.label!,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 3),
          content,
        ],
      );
    }

    return content;
  }
}
