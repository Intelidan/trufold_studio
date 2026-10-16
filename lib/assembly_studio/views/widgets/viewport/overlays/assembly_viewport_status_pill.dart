// Top-Right Status Pill (OSHA/ISO Compliance & Cut List / BOM)
// Modularized for TruFold MVVM Architecture

import 'package:flutter/material.dart';
import 'package:trufold_studio/assembly_studio/viewmodels/assembly_studio_viewmodel.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';

class AssemblyViewportStatusPill extends StatelessWidget {
  final AssemblyStudioViewModel viewModel;
  final VoidCallback onShowComplianceAuditDialog;
  final VoidCallback onShowBomDialog;

  const AssemblyViewportStatusPill({
    super.key,
    required this.viewModel,
    required this.onShowComplianceAuditDialog,
    required this.onShowBomDialog,
  });

  @override
  Widget build(BuildContext context) {
    final report = viewModel.evaluateLadderCompliance();
    final isGpu = viewModel.renderEngine == Cad3dEngineMode.flutterGpu;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Active 3D Render Engine Selector Pill (GPU vs 2D Canvas)
        Theme(
          data: Theme.of(context).copyWith(
            hoverColor: const Color(0xFFF1F5F9),
          ),
          child: PopupMenuButton<Cad3dEngineMode>(
            tooltip: '3D Render Engine: ${viewModel.renderEngine.label}\nClick to switch between GPU and 2D Canvas',
            initialValue: viewModel.renderEngine,
            onSelected: (mode) => viewModel.setRenderEngine(mode),
            color: Colors.white,
            elevation: 6,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: Color(0xFFCBD5E1)),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isGpu ? const Color(0xFF10B981) : const Color(0xFF0284C7),
                  width: 1.2,
                ),
                boxShadow: const [
                  BoxShadow(color: Color(0x15000000), blurRadius: 8, offset: Offset(0, 2)),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isGpu ? Icons.speed_rounded : Icons.brush_rounded,
                    color: isGpu ? const Color(0xFF059669) : const Color(0xFF0284C7),
                    size: 14,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    isGpu ? '⚡ GPU (flutter_scene)' : '🎨 2D Canvas (Paint)',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: isGpu ? const Color(0xFF047857) : const Color(0xFF0369A1),
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(
                    Icons.arrow_drop_down_rounded,
                    size: 16,
                    color: isGpu ? const Color(0xFF047857) : const Color(0xFF0369A1),
                  ),
                ],
              ),
            ),
            itemBuilder: (ctx) => [
              PopupMenuItem<Cad3dEngineMode>(
                value: Cad3dEngineMode.flutterGpu,
                child: Row(
                  children: [
                    Icon(
                      Icons.speed_rounded,
                      size: 18,
                      color: isGpu ? const Color(0xFF059669) : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const Text('Flutter GPU (flutter_scene)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            if (isGpu) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDCFCE7),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('ACTIVE', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Color(0xFF15803D))),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        const Text('Hardware-accelerated 120 FPS PBR renderer', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuItem<Cad3dEngineMode>(
                value: Cad3dEngineMode.flutterPaint,
                child: Row(
                  children: [
                    Icon(
                      Icons.brush_rounded,
                      size: 18,
                      color: !isGpu ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const Text('2D Canvas (FlutterPaint)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            if (!isGpu) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE0F2FE),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('ACTIVE', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Color(0xFF0369A1))),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        const Text('Pure software CustomPainter Canvas fallback', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Live OSHA / ISO Compliance Badge
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onShowComplianceAuditDialog,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: report.badgeColor.withValues(alpha: 0.95),
                width: 1.2,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x15000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  report.isCompliant ? Icons.verified_rounded : Icons.warning_amber_rounded,
                  color: report.badgeColor,
                  size: 15,
                ),
                const SizedBox(width: 6),
                Text(
                  report.badgeLabel,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: report.badgeColor,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),

        // BOM & Cut List Pill Button
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onShowBomDialog,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF0076CE).withValues(alpha: 0.8),
                width: 1.0,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x15000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.inventory_2_rounded,
                  color: Color(0xFF0076CE),
                  size: 14,
                ),
                SizedBox(width: 5),
                Text(
                  'Cut List / BOM',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0076CE),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
