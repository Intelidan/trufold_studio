// Bottom Quick Action Bar (Selected Part Title & Direct Sketch Button)
// Modularized for TruFold MVVM Architecture

import 'package:flutter/material.dart';
import 'package:trufold_studio/assembly_studio/viewmodels/assembly_studio_viewmodel.dart';

class AssemblyQuickActionBar extends StatelessWidget {
  final AssemblyStudioViewModel viewModel;

  const AssemblyQuickActionBar({
    super.key,
    required this.viewModel,
  });

  @override
  Widget build(BuildContext context) {
    final part = viewModel.selectedPart;
    if (part == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 1.0),
        boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 10, offset: Offset(0, 3))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              part.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF0F172A)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            icon: const Icon(Icons.edit_note_rounded, size: 16),
            label: const Text('Direct Sketch (S)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            onPressed: () => viewModel.focusPartAndEnterSketch(part.id),
          ),
          const SizedBox(width: 8),
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              viewModel.selectPart(null);
            },
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close_rounded, size: 16, color: Color(0xFF64748B)),
            ),
          ),
        ],
      ),
    );
  }
}
