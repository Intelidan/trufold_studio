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
    final isLight = viewModel.isLightBackground;
    final hasContent = controller.text.isNotEmpty || viewModel.vcbValue.isNotEmpty;

    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: isLight
            ? const Color(0xFFFFFFFF).withValues(alpha: 0.96)
            : const Color(0xFF0F172A).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: focusNode.hasFocus
              ? const Color(0xFF38BDF8)
              : (isLight ? const Color(0xFFCBD5E1) : const Color(0xFF334155)),
          width: focusNode.hasFocus ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isLight ? const Color(0x18000000) : Colors.black.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.40)),
                  ),
                  child: Text(
                    viewModel.vcbLabel.toUpperCase(),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: const TextStyle(
                      color: Color(0xFF0284C7),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              if (hasContent)
                GestureDetector(
                  onTap: onClear,
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: isLight ? const Color(0xFF64748B) : Colors.white54,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: isLight ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isLight ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    style: TextStyle(
                      color: isLight ? const Color(0xFF0F172A) : Colors.white,
                      fontSize: 13,
                      fontFamily: 'RobotoMono',
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      hintText: viewModel.vcbHint,
                      hintStyle: TextStyle(
                        color: isLight ? const Color(0xFF94A3B8) : Colors.white38,
                        fontSize: 11,
                        fontFamily: 'sans-serif',
                      ),
                    ),
                    onChanged: onChanged,
                    onSubmitted: onSubmitted,
                  ),
                ),
                if (hasContent)
                  IconButton(
                    icon: const Icon(Icons.keyboard_return, size: 14, color: Color(0xFF0284C7)),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Submit (Enter)',
                    onPressed: () => onSubmitted(controller.text.trim()),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
