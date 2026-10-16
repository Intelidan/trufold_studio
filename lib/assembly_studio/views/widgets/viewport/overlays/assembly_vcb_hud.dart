// SketchUp Measurements VCB HUD (Bottom-Right)
// Modularized for TruFold MVVM Architecture

import 'package:flutter/material.dart';
import 'package:trufold_studio/assembly_studio/viewmodels/assembly_studio_viewmodel.dart';

class AssemblyVcbHud extends StatelessWidget {
  final AssemblyStudioViewModel viewModel;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onClear;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  const AssemblyVcbHud({
    super.key,
    required this.viewModel,
    required this.controller,
    required this.focusNode,
    required this.onClear,
    required this.onChanged,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final hasContent = controller.text.isNotEmpty || viewModel.vcbValue.isNotEmpty;

    return Container(
      constraints: const BoxConstraints(minWidth: 170, maxWidth: 240),
      height: 28,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: focusNode.hasFocus ? const Color(0xFF0076CE) : const Color(0xFFCBD5E1),
          width: focusNode.hasFocus ? 1.4 : 1.0,
        ),
        boxShadow: const [BoxShadow(color: Color(0x18000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. Compact Label Pill (Flexible to prevent overflow on long labels like '🔒 WELDED ENTITY')
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: const Color(0xFFE0F2FE),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: const Color(0xFFBAE6FD), width: 0.8),
              ),
              child: Text(
                viewModel.vcbLabel.toUpperCase(),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: const TextStyle(
                  color: Color(0xFF0076CE),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
          const SizedBox(width: 5),


          // 2. Compact Value Field
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 11.5,
                fontFamily: 'RobotoMono',
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintText: viewModel.vcbHint,
                hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontFamily: 'sans-serif'),
              ),
              onChanged: onChanged,
              onSubmitted: onSubmitted,
            ),
          ),

          // 3. Clear / Submit Controls
          if (hasContent) ...[
            GestureDetector(
              onTap: onClear,
              child: const Icon(Icons.close, size: 12, color: Color(0xFF94A3B8)),
            ),
            const SizedBox(width: 3),
            GestureDetector(
              onTap: () => onSubmitted(controller.text.trim()),
              child: const Icon(Icons.keyboard_return_rounded, size: 13, color: Color(0xFF0076CE)),
            ),
          ],
        ],
      ),
    );
  }
}
