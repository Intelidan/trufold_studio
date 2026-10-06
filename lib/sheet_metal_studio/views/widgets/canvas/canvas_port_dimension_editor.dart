// =============================================================================
// CanvasPortDimensionEditorMixin
//
// Provides port-driven parametric dimension editor state + logic for
// _UnfoldedCanvasWidgetState. Extracted from unfolded_canvas_widget.dart.
// =============================================================================

part of '../unfolded_canvas_widget.dart';

/// Mixin that contributes port-dimension-editor state and methods to
/// [_UnfoldedCanvasWidgetState].
mixin CanvasPortDimensionEditorMixin on State<UnfoldedCanvasWidget> {
  // ---------------------------------------------------------------------------
  // Port Dimension Editor State
  // ---------------------------------------------------------------------------

  String? _activeEditingPortId;
  double _portEditWidth = 300.0;
  double _portEditHeightA = 50.0;
  double _portEditHeightB = 50.0;
  bool _portHeightsLinked = true;
  Map<String, double> _portEditBaselineParams = {};
  Offset? _portEditorScreenPos;

  // Port badge rects tracked by the painter (shared with gesture handler)
  final Map<String, Rect> _portBadgeRects = {};
  String? _draggedPortBadgeId;
  Offset _dragPortBadgeStartOffset = Offset.zero;
  String? _hoveredPortBadgeId;
  bool _hasMovedPortBadge = false;

  // ---------------------------------------------------------------------------
  // Open / Close Helpers
  // ---------------------------------------------------------------------------

  void _openPortDimensionEditor(String portBadgeId) {
    // Extract base port id (e.g. 'port1' from 'port1' or 'port1_h_0')
    final portId = portBadgeId.split('_').first;
    final meta =
        widget.viewModel.detectedFittingMetadata ??
        DxfFittingMetadata.fromDocument(widget.viewModel.document) ??
        const DxfFittingMetadata();
    final ports = FittingPortAnnotationEngine.detectPortOpenings(
      document: widget.viewModel.document,
      metadata: meta,
    );
    final port = ports.where((p) => p.id == portId).firstOrNull;
    final semantic = meta.semanticPorts?[portId];

    final portNumStr = portId.replaceAll(RegExp(r'[^0-9]'), '');
    final currentW =
        (semantic?['width'] as num?)?.toDouble() ??
        port?.widthMm ??
        widget.viewModel.document.parameters['port${portNumStr}_width'] ??
        widget.viewModel.document.parameters['port${portNumStr}Width'] ??
        widget.viewModel.document.parameters['width'] ??
        300.0;
    final currentHA =
        (semantic?['heightA'] as num?)?.toDouble() ??
        port?.heightAMm ??
        port?.heightMm ??
        widget.viewModel.document.parameters['port${portNumStr}_height'] ??
        widget.viewModel.document.parameters['port${portNumStr}HeightA'] ??
        widget.viewModel.document.parameters['port${portNumStr}Height'] ??
        widget.viewModel.document.parameters['heightA'] ??
        widget.viewModel.document.parameters['height'] ??
        50.0;
    final currentHB =
        (semantic?['heightB'] as num?)?.toDouble() ??
        port?.heightBMm ??
        port?.heightMm ??
        widget.viewModel.document.parameters['port${portNumStr}_height'] ??
        widget.viewModel.document.parameters['port${portNumStr}HeightB'] ??
        widget.viewModel.document.parameters['port${portNumStr}Height'] ??
        widget.viewModel.document.parameters['heightB'] ??
        widget.viewModel.document.parameters['height'] ??
        50.0;

    final badgeRect = _portBadgeRects[portBadgeId];
    Offset pos = const Offset(60, 100);
    if (badgeRect != null) {
      pos = Offset(badgeRect.center.dx - 140, badgeRect.bottom + 12);
    }

    setState(() {
      _activeEditingPortId = portId;
      _portEditWidth = currentW;
      _portEditHeightA = currentHA;
      _portEditHeightB = currentHB;
      _portHeightsLinked = (_portEditHeightA - _portEditHeightB).abs() < 1e-3;
      _portEditorScreenPos = pos;
      _portEditBaselineParams = Map<String, double>.from(
        widget.viewModel.document.parameters,
      );
    });
  }

  ({String widthKey, String heightAKey, String heightBKey})
  _resolveParamKeysForPort(
    String portId,
    DxfFittingMetadata? meta,
    Map<String, double> params,
  ) {
    final portNum = int.tryParse(portId.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1;

    String? wKey;
    String? haKey;
    String? hbKey;

    if (params.containsKey('port${portNum}_width')) {
      wKey = 'port${portNum}_width';
    } else if (params.containsKey('port${portNum}Width')) {
      wKey = 'port${portNum}Width';
    }

    if (params.containsKey('port${portNum}_height')) {
      haKey = 'port${portNum}_height';
      hbKey = 'port${portNum}_height';
    } else if (params.containsKey('port${portNum}HeightA')) {
      haKey = 'port${portNum}HeightA';
    } else if (params.containsKey('port${portNum}Height')) {
      haKey = 'port${portNum}Height';
    }

    if (params.containsKey('port${portNum}HeightB')) {
      hbKey = 'port${portNum}HeightB';
    }

    if (wKey == null) {
      if (portNum == 1) {
        if (params.containsKey('widthIn')) {
          wKey = 'widthIn';
        } else if (params.containsKey('widthMain')) {
          wKey = 'widthMain';
        } else if (params.containsKey('width')) {
          wKey = 'width';
        }
      } else if (portNum == 2) {
        if (params.containsKey('widthOut')) {
          wKey = 'widthOut';
        } else if (params.containsKey('widthMain')) {
          wKey = 'widthMain';
        } else if (params.containsKey('width')) {
          wKey = 'width';
        }
      } else if (portNum == 3) {
        if (params.containsKey('branchWidth')) {
          wKey = 'branchWidth';
        } else if (params.containsKey('widthBranch')) {
          wKey = 'widthBranch';
        }
      } else if (portNum == 4) {
        if (params.containsKey('widthBranch')) {
          wKey = 'widthBranch';
        }
      }
      wKey ??= 'port${portNum}_width';
    }

    if (haKey == null) {
      if (params.containsKey('heightA')) {
        haKey = 'heightA';
      } else if (params.containsKey('height')) {
        haKey = 'height';
      } else if (params.containsKey('port${portNum}_height')) {
        haKey = 'port${portNum}_height';
      } else if (params.containsKey('port${portNum}Height')) {
        haKey = 'port${portNum}Height';
      } else {
        haKey = 'port${portNum}_height';
      }
    }

    if (hbKey == null) {
      if (params.containsKey('heightB')) {
        hbKey = 'heightB';
      } else if (params.containsKey('height')) {
        hbKey = 'height';
      } else if (params.containsKey('port${portNum}_height')) {
        hbKey = 'port${portNum}_height';
      } else if (params.containsKey('port${portNum}Height')) {
        hbKey = 'port${portNum}Height';
      } else {
        hbKey = 'port${portNum}_height';
      }
    }

    return (widthKey: wKey, heightAKey: haKey, heightBKey: hbKey);
  }

  void _updateLivePortDimension({double? newW, double? newHA, double? newHB}) {
    if (_activeEditingPortId == null) return;
    final meta =
        widget.viewModel.detectedFittingMetadata ??
        DxfFittingMetadata.fromDocument(widget.viewModel.document);
    final keys = _resolveParamKeysForPort(
      _activeEditingPortId!,
      meta,
      widget.viewModel.document.parameters,
    );

    if (newW != null) {
      _portEditWidth = newW;
      widget.viewModel.updateTemplateParameter(keys.widthKey, newW);
    }
    if (newHA != null) {
      _portEditHeightA = newHA;
      widget.viewModel.updateTemplateParameter(keys.heightAKey, newHA);
      if (keys.heightAKey != 'height' &&
          widget.viewModel.document.parameters.containsKey('height')) {
        widget.viewModel.updateTemplateParameter('height', newHA);
      }
      if (_portHeightsLinked) {
        _portEditHeightB = newHA;
        widget.viewModel.updateTemplateParameter(keys.heightBKey, newHA);
      }
    }
    if (newHB != null && !_portHeightsLinked) {
      _portEditHeightB = newHB;
      widget.viewModel.updateTemplateParameter(keys.heightBKey, newHB);
    }
    setState(() {});
  }

  void _applyPortDimensionEditor() {
    if (_activeEditingPortId == null) return;
    final meta =
        widget.viewModel.detectedFittingMetadata ??
        DxfFittingMetadata.fromDocument(widget.viewModel.document) ??
        const DxfFittingMetadata();

    final existingSemantic = meta.semanticPorts?[_activeEditingPortId!] ?? {};
    final updatedSemantic = Map<String, dynamic>.from(existingSemantic)
      ..['width'] = _portEditWidth
      ..['heightA'] = _portEditHeightA
      ..['heightB'] = _portEditHeightB;

    final updatedMeta = meta.copyWith(
      semanticPorts: {
        ...?meta.semanticPorts,
        _activeEditingPortId!: updatedSemantic,
      },
    );
    widget.viewModel.updateFittingMetadata(updatedMeta);
    widget.viewModel.commitCmsScaling();
    setState(() {
      _activeEditingPortId = null;
    });
  }

  void _cancelPortDimensionEditor() {
    if (_activeEditingPortId == null) return;
    for (final entry in _portEditBaselineParams.entries) {
      widget.viewModel.updateTemplateParameter(entry.key, entry.value);
    }
    if (widget.viewModel.scalingController != null) {
      widget.viewModel.exitTeachScaling();
    }
    setState(() {
      _activeEditingPortId = null;
    });
  }

  // ---------------------------------------------------------------------------
  // Port Dimension Editor Card Widget
  // ---------------------------------------------------------------------------

  Widget _buildPortDimensionEditorCard(SheetMetalStudioViewModel viewModel) {
    if (_activeEditingPortId == null) return const SizedBox.shrink();
    final meta =
        viewModel.detectedFittingMetadata ??
        DxfFittingMetadata.fromDocument(viewModel.document);
    final ports = FittingPortAnnotationEngine.detectPortOpenings(
      document: viewModel.document,
      metadata: meta,
    );
    final port = ports.where((p) => p.id == _activeEditingPortId).firstOrNull;
    final portTitle = port?.label ?? _activeEditingPortId!.toUpperCase();
    final sideName = port?.side.displayName ?? 'Port';

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 280,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A).withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF0EA5E9), width: 1.6),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Title, Link/Unlock toggle, and Close
            Row(
              children: [
                const Icon(Icons.adjust, size: 16, color: Color(0xFF38BDF8)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$portTitle ($sideName)',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InkWell(
                  onTap: () {
                    setState(() {
                      _portHeightsLinked = !_portHeightsLinked;
                      if (_portHeightsLinked) {
                        _updateLivePortDimension(newHB: _portEditHeightA);
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _portHeightsLinked
                          ? const Color(0xFF10B981).withValues(alpha: 0.2)
                          : const Color(0xFFF59E0B).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: _portHeightsLinked
                            ? const Color(0xFF10B981)
                            : const Color(0xFFF59E0B),
                        width: 0.9,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _portHeightsLinked ? Icons.link : Icons.link_off,
                          size: 13,
                          color: _portHeightsLinked
                              ? const Color(0xFF34D399)
                              : const Color(0xFFFBBF24),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          _portHeightsLinked ? 'Linked' : 'Async',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: _portHeightsLinked
                                ? const Color(0xFF34D399)
                                : const Color(0xFFFBBF24),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: _cancelPortDimensionEditor,
                  child: const Icon(
                    Icons.close,
                    size: 16,
                    color: Colors.white54,
                  ),
                ),
              ],
            ),
            const Divider(color: Colors.white24, height: 14),

            // Dimension 1: Width
            _buildDimensionRow(
              label: 'Width (W)',
              value: _portEditWidth,
              step: 25.0,
              min: 50.0,
              max: 1200.0,
              accentColor: const Color(0xFF38BDF8),
              onChanged: (newVal) => _updateLivePortDimension(newW: newVal),
            ),
            const SizedBox(height: 8),

            // Dimension 2: Height A
            _buildDimensionRow(
              label: 'Height A (HA)',
              value: _portEditHeightA,
              step: 25.0,
              min: 25.0,
              max: 200.0,
              accentColor: const Color(0xFFF59E0B),
              onChanged: (newVal) => _updateLivePortDimension(newHA: newVal),
            ),
            const SizedBox(height: 8),

            // Dimension 3: Height B
            _buildDimensionRow(
              label: _portHeightsLinked ? 'Height B (HA 🔗)' : 'Height B (HB)',
              value: _portEditHeightB,
              step: 25.0,
              min: 25.0,
              max: 200.0,
              accentColor: const Color(0xFF8B5CF6),
              enabled: !_portHeightsLinked,
              onChanged: (newVal) => _updateLivePortDimension(newHB: newVal),
            ),
            const SizedBox(height: 12),

            // Action row: Apply (Enter) & Cancel (Esc)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _cancelPortDimensionEditor,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white60,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text(
                    'Cancel (Esc)',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _applyPortDimensionEditor,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.check, size: 14),
                  label: const Text(
                    'Apply (Enter)',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDimensionRow({
    required String label,
    required double value,
    required double step,
    required double min,
    required double max,
    required Color accentColor,
    required ValueChanged<double> onChanged,
    bool enabled = true,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: enabled ? 0.07 : 0.03),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: enabled
              ? Colors.white12
              : Colors.white.withValues(alpha: 0.04),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: enabled ? const Color(0xFFE2E8F0) : Colors.white38,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          InkWell(
            onTap: enabled
                ? () {
                    final next = (value - step).clamp(min, max);
                    onChanged(next);
                  }
                : null,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: enabled ? 0.12 : 0.05),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                Icons.remove,
                size: 13,
                color: enabled ? Colors.white70 : Colors.white24,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            constraints: const BoxConstraints(minWidth: 46),
            alignment: Alignment.center,
            child: Text(
              '${value.toStringAsFixed(0)} mm',
              style: TextStyle(
                color: enabled ? accentColor : Colors.white38,
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: enabled
                ? () {
                    final next = (value + step).clamp(min, max);
                    onChanged(next);
                  }
                : null,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: enabled ? 0.12 : 0.05),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                Icons.add,
                size: 13,
                color: enabled ? Colors.white70 : Colors.white24,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
