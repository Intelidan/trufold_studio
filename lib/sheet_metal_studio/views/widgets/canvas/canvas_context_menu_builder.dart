// =============================================================================
// CanvasContextMenuMixin
//
// Provides right-click edge context-menu state + menu-item builder for
// _UnfoldedCanvasWidgetState. Extracted from unfolded_canvas_widget.dart.
// =============================================================================

part of '../unfolded_canvas_widget.dart';

/// Mixin that contributes the right-click edge port-assignment context-menu to
/// [_UnfoldedCanvasWidgetState].
mixin CanvasContextMenuMixin on State<UnfoldedCanvasWidget> {
  // ---------------------------------------------------------------------------
  // Context Menu State
  // ---------------------------------------------------------------------------

  /// Controller for the edge right-click MenuAnchor.
  final MenuController _contextMenuController = MenuController();
  CadPoint2D? _contextMenuP1;
  CadPoint2D? _contextMenuP2;
  double? _contextMenuLenMm;

  // ---------------------------------------------------------------------------
  // Menu-children builder
  // ---------------------------------------------------------------------------

  List<Widget> _buildEdgeContextMenuChildren(
    SheetMetalStudioViewModel viewModel,
  ) {
    if (_contextMenuP1 == null || _contextMenuP2 == null) return const [];
    final p1 = _contextMenuP1!;
    final p2 = _contextMenuP2!;
    final lenMm = _contextMenuLenMm ?? p1.distanceTo(p2);
    final assigned = viewModel.findAssignedPortForEdge(p1, p2);
    final meta =
        viewModel.detectedFittingMetadata ??
        DxfFittingMetadata.fromDocument(viewModel.document);
    final portCount = meta != null
        ? ProductCatalogService.getPortCount(meta.product, meta.variantName)
        : 2;

    return [
      MenuItemButton(
        onPressed: null,
        child: Text(
          'Edge: ${lenMm.toStringAsFixed(1)} mm${assigned != null ? ' ($assigned)' : ''}',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 11,
            color: Color(0xFF0F172A),
          ),
        ),
      ),
      const Divider(height: 1),
      SubmenuButton(
        menuChildren: [
          for (int i = 1; i <= portCount; i++) ...[
            SubmenuButton(
              menuChildren: [
                MenuItemButton(
                  onPressed: () {
                    final err = viewModel.assignPortEdgeDirect(
                      portId: 'port$i',
                      isWidth: true,
                      p1: p1,
                      p2: p2,
                      measuredLengthMm: lenMm,
                    );
                    if (err != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('⚠️ $err'),
                          backgroundColor: const Color(0xFFDC2626),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '✓ Assigned Port $i Width (${lenMm.toStringAsFixed(1)} mm)',
                          ),
                          backgroundColor: const Color(0xFF0D9488),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  leadingIcon: const Icon(
                    Icons.straighten,
                    size: 16,
                    color: Color(0xFF0284C7),
                  ),
                  child: const Text('Assign as Width (W) Edge'),
                ),
                MenuItemButton(
                  onPressed: () {
                    final err = viewModel.assignPortEdgeDirect(
                      portId: 'port$i',
                      isWidth: false,
                      p1: p1,
                      p2: p2,
                      measuredLengthMm: lenMm,
                    );
                    if (err != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('⚠️ $err'),
                          backgroundColor: const Color(0xFFDC2626),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '✓ Assigned Port $i Height Flap (${lenMm.toStringAsFixed(1)} mm)',
                          ),
                          backgroundColor: const Color(0xFF0D9488),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  leadingIcon: const Icon(
                    Icons.border_top,
                    size: 16,
                    color: Color(0xFF0D9488),
                  ),
                  child: const Text('Assign as Height (H) Flap Edge'),
                ),
              ],
              child: Text(
                i == 1
                    ? 'Port 1 (Inlet)'
                    : (i == 2
                          ? 'Port 2 (Outlet)'
                          : (i == 3 ? 'Port 3 (Branch)' : 'Port $i')),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
        leadingIcon: const Icon(
          Icons.input,
          size: 16,
          color: Color(0xFF0284C7),
        ),
        child: const Text(
          'Assign Port',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      if (assigned != null) ...[
        const Divider(height: 1),
        MenuItemButton(
          onPressed: () {
            viewModel.clearAssignedPortEdge(p1, p2);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Removed assignment from edge ($assigned)'),
                duration: const Duration(seconds: 2),
              ),
            );
          },
          leadingIcon: const Icon(
            Icons.clear,
            size: 16,
            color: Color(0xFFEF4444),
          ),
          child: Text(
            'Clear Assignment ($assigned)',
            style: const TextStyle(color: Color(0xFFEF4444)),
          ),
        ),
      ],
      const Divider(height: 1),
      MenuItemButton(
        onPressed: () => viewModel.setFittingInspectorOpen(true),
        leadingIcon: const Icon(Icons.tune, size: 16, color: Color(0xFF64748B)),
        child: const Text('Fitting Inspector...'),
      ),
    ];
  }
}
