// =============================================================================
// canvas_display_settings_dialog.dart
//
// A rich, tabbed settings dialog for all 2D canvas display preferences.
// Accessible from View â†’ Canvas Display Settings.
// =============================================================================

import 'package:flutter/material.dart';

import '../../../models/canvas_display_settings.dart';
import '../../../viewmodels/sheet_metal_studio_viewmodel.dart';

/// Opens the [CanvasDisplaySettingsDialog] and applies any changes to [vm].
Future<void> showCanvasDisplaySettingsDialog(
  BuildContext context,
  SheetMetalStudioViewModel vm,
) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Canvas Display Settings',
    barrierColor: Colors.black26,
    transitionDuration: const Duration(milliseconds: 180),
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(
      opacity: anim,
      child: ScaleTransition(
        scale: Tween<double>(
          begin: 0.96,
          end: 1.0,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
        child: child,
      ),
    ),
    pageBuilder: (ctx, _, _) => CanvasDisplaySettingsDialog(
      initial: vm.canvasDisplaySettings,
      onChanged: vm.updateCanvasDisplaySettings,
    ),
  );
}

// ---------------------------------------------------------------------------
// Dialog widget
// ---------------------------------------------------------------------------

class CanvasDisplaySettingsDialog extends StatefulWidget {
  const CanvasDisplaySettingsDialog({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  final CanvasDisplaySettings initial;
  final ValueChanged<CanvasDisplaySettings> onChanged;

  @override
  State<CanvasDisplaySettingsDialog> createState() =>
      _CanvasDisplaySettingsDialogState();
}

class _CanvasDisplaySettingsDialogState
    extends State<CanvasDisplaySettingsDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late CanvasDisplaySettings _settings;

  // Draggable position â€” null means "start at centre of screen".
  Offset? _dialogOffset;

  static const _tabLabels = [
    'Units & Scale',
    'Bend Labels',
    'Face Labels',
    'Dim & Arc',
    'Canvas',
  ];

  @override
  void initState() {
    super.initState();
    _settings = widget.initial;
    _tabs = TabController(length: _tabLabels.length, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _update(CanvasDisplaySettings next) {
    setState(() => _settings = next);
    widget.onChanged(next); // live preview
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    const dialogW = 580.0;
    const dialogH = 560.0;

    // Default: horizontally centred, 60 px from top.
    final defaultOffset = Offset(
      (screenSize.width - dialogW) / 2,
      (screenSize.height - dialogH) / 2,
    );
    final offset = _dialogOffset ?? defaultOffset;

    return Stack(
      children: [
        Positioned(
          left: offset.dx,
          top: offset.dy,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: dialogW,
              height: dialogH,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFCBD5E1)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(screenSize, dialogW, dialogH),
                    _buildTabBar(),
                    Expanded(
                      child: TabBarView(
                        controller: _tabs,
                        children: [
                          _UnitsTab(settings: _settings, onChanged: _update),
                          _LabelStyleTab(
                            title: 'Bend & Flange Labels',
                            icon: Icons.architecture,
                            iconColor: const Color(0xFF0369A1),
                            style: _settings.bendLabel,
                            onChanged: (s) =>
                                _update(_settings.copyWith(bendLabel: s)),
                            extra: _BendThresholdSection(
                              settings: _settings,
                              onChanged: _update,
                            ),
                          ),
                          _LabelStyleTab(
                            title: 'Face / Panel Labels',
                            icon: Icons.crop_square,
                            iconColor: const Color(0xFF0891B2),
                            style: _settings.faceLabel,
                            onChanged: (s) =>
                                _update(_settings.copyWith(faceLabel: s)),
                            extra: _FaceDeclutterSection(
                              settings: _settings,
                              onChanged: _update,
                            ),
                          ),
                          _DimArcTab(settings: _settings, onChanged: _update),
                          _CanvasTab(settings: _settings, onChanged: _update),
                        ],
                      ),
                    ),
                    _buildFooter(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(Size screenSize, double dialogW, double dialogH) {
    const headerH = 48.0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (details) {
        setState(() {
          final current =
              _dialogOffset ??
              Offset(
                (screenSize.width - dialogW) / 2,
                (screenSize.height - dialogH) / 2,
              );
          _dialogOffset = Offset(
            (current.dx + details.delta.dx).clamp(
              0.0,
              screenSize.width - dialogW,
            ),
            (current.dy + details.delta.dy).clamp(
              0.0,
              screenSize.height - headerH,
            ),
          );
        });
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.move,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: const BoxDecoration(
            color: Color(0xFF0F172A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.display_settings,
                color: Color(0xFF38BDF8),
                size: 20,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Canvas Display Settings',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.close,
                  color: Color(0xFF94A3B8),
                  size: 18,
                ),
                onPressed: () => Navigator.of(context).pop(),
                splashRadius: 16,
                tooltip: 'Close',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF1F5F9),
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: TabBar(
        controller: _tabs,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: const Color(0xFF0369A1),
        unselectedLabelColor: const Color(0xFF64748B),
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        indicator: const UnderlineTabIndicator(
          borderSide: BorderSide(color: Color(0xFF0369A1), width: 2.5),
        ),
        tabs: _tabLabels.map((l) => Tab(text: l)).toList(),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 13, color: Color(0xFF64748B)),
          const SizedBox(width: 6),
          const Expanded(
            child: Text(
              'Changes apply live to the canvas.',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 11.5),
            ),
          ),
          TextButton(
            onPressed: () {
              _update(const CanvasDisplaySettings());
            },
            child: const Text(
              'Reset Defaults',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0369A1),
              textStyle: const TextStyle(fontSize: 12),
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab: Units & Scale
// ---------------------------------------------------------------------------

class _UnitsTab extends StatelessWidget {
  const _UnitsTab({required this.settings, required this.onChanged});
  final CanvasDisplaySettings settings;
  final ValueChanged<CanvasDisplaySettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader('Unit of Measure'),
          const SizedBox(height: 10),
          ...CanvasUom.values.map(
            (uom) => InkWell(
              onTap: () => onChanged(settings.copyWith(uom: uom)),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Row(
                  children: [
                    // ignore: deprecated_member_use
                    Radio<CanvasUom>(
                      value: uom,
                      // ignore: deprecated_member_use
                      groupValue: settings.uom,
                      activeColor: const Color(0xFF0369A1),
                      // ignore: deprecated_member_use
                      onChanged: (_) => onChanged(settings.copyWith(uom: uom)),
                    ),
                    const SizedBox(width: 4),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          uom.displayName,
                          style: const TextStyle(fontSize: 13),
                        ),
                        Text(
                          _uomHint(uom),
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _SectionHeader('Decimal Places'),
          const SizedBox(height: 8),
          _SettingRow(
            label: 'Decimal places for mm / decimal-inch',
            child: DropdownButton<int>(
              value: settings.decimalPlaces,
              items: [0, 1, 2, 3]
                  .map(
                    (v) =>
                        DropdownMenuItem(value: v, child: Text(v.toString())),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  onChanged(settings.copyWith(decimalPlaces: v));
                }
              },
            ),
          ),
          const SizedBox(height: 20),
          _SectionHeader('Preview'),
          const SizedBox(height: 8),
          _PreviewChip(
            'Face: ${formatDimPair(131.9, 98.0, settings)}',
            const Color(0xFFE0F2FE),
          ),
          const SizedBox(height: 6),
          _PreviewChip(
            'Bend length: ${formatMeasure(101.7, settings)}',
            const Color(0xFFEDE9FE),
          ),
        ],
      ),
    );
  }

  String _uomHint(CanvasUom uom) => switch (uom) {
    CanvasUom.mm => 'e.g.  131.9 Ã— 98.0 mm',
    CanvasUom.inch => 'e.g.  5.19 Ã— 3.86"',
    CanvasUom.fractionalInch => 'e.g.  5-3/16 Ã— 3-7/8"',
  };
}

// ---------------------------------------------------------------------------
// Tab: Generic Label Style (used for Bend and Face tabs)
// ---------------------------------------------------------------------------

class _LabelStyleTab extends StatelessWidget {
  const _LabelStyleTab({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.style,
    required this.onChanged,
    this.extra,
  });

  final String title;
  final IconData icon;
  final Color iconColor;
  final LabelStyle style;
  final ValueChanged<LabelStyle> onChanged;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 16),
              const SizedBox(width: 8),
              _SectionHeader(title),
            ],
          ),
          const SizedBox(height: 14),
          _ToggleRow(
            label: 'Show labels',
            value: style.visible,
            onChanged: (v) => onChanged(style.copyWith(visible: v)),
          ),
          const SizedBox(height: 16),
          _FontSizeSlider(
            value: style.fontSize,
            min: 7.0,
            max: 16.0,
            onChanged: (v) => onChanged(style.copyWith(fontSize: v)),
          ),
          const SizedBox(height: 16),
          _WeightRow(
            value: style.fontWeight,
            onChanged: (w) => onChanged(style.copyWith(fontWeight: w)),
          ),
          const SizedBox(height: 16),
          _ColorRow(
            label: 'Label colour',
            color: style.color,
            onChanged: (c) => onChanged(style.copyWith(color: c)),
          ),
          if (extra != null) ...[
            const SizedBox(height: 20),
            const Divider(color: Color(0xFFE2E8F0)),
            const SizedBox(height: 12),
            extra!,
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bend-specific extras (zoom thresholds)
// ---------------------------------------------------------------------------

class _BendThresholdSection extends StatelessWidget {
  const _BendThresholdSection({
    required this.settings,
    required this.onChanged,
  });
  final CanvasDisplaySettings settings;
  final ValueChanged<CanvasDisplaySettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader('Zoom-Adaptive Declutter'),
        const SizedBox(height: 8),
        _SliderRow(
          label: 'Compact mode below zoom',
          value: settings.bendLabelCompactZoomThreshold,
          min: 0.1,
          max: 1.5,
          divisions: 14,
          format: (v) => '${v.toStringAsFixed(2)}Ã—',
          onChanged: (v) =>
              onChanged(settings.copyWith(bendLabelCompactZoomThreshold: v)),
        ),
        const SizedBox(height: 8),
        _SliderRow(
          label: 'Hide labels below zoom',
          value: settings.bendLabelHideZoomThreshold,
          min: 0.05,
          max: 1.0,
          divisions: 19,
          format: (v) => '${v.toStringAsFixed(2)}Ã—',
          onChanged: (v) =>
              onChanged(settings.copyWith(bendLabelHideZoomThreshold: v)),
        ),
        const SizedBox(height: 6),
        const Text(
          'Labels shrink to ID + angle at "compact" zoom, and vanish entirely below "hide" zoom.',
          style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Face-specific extras (min screen size)
// ---------------------------------------------------------------------------

class _FaceDeclutterSection extends StatelessWidget {
  const _FaceDeclutterSection({
    required this.settings,
    required this.onChanged,
  });
  final CanvasDisplaySettings settings;
  final ValueChanged<CanvasDisplaySettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader('Declutter Threshold'),
        const SizedBox(height: 8),
        _SliderRow(
          label: 'Min face screen size to show label',
          value: settings.faceLabelMinScreenSize,
          min: 16.0,
          max: 160.0,
          divisions: 18,
          format: (v) => '${v.toStringAsFixed(0)} px',
          onChanged: (v) =>
              onChanged(settings.copyWith(faceLabelMinScreenSize: v)),
        ),
        const SizedBox(height: 6),
        const Text(
          'Labels are suppressed when the face is smaller than this on screen.',
          style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tab: Dimension & Arc Labels
// ---------------------------------------------------------------------------

class _DimArcTab extends StatelessWidget {
  const _DimArcTab({required this.settings, required this.onChanged});
  final CanvasDisplaySettings settings;
  final ValueChanged<CanvasDisplaySettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader('Dimension Text Labels'),
          const SizedBox(height: 10),
          _ToggleRow(
            label: 'Show dimension text',
            value: settings.dimTextLabel.visible,
            onChanged: (v) => onChanged(
              settings.copyWith(
                dimTextLabel: settings.dimTextLabel.copyWith(visible: v),
              ),
            ),
          ),
          _FontSizeSlider(
            value: settings.dimTextLabel.fontSize,
            min: 7,
            max: 14,
            onChanged: (v) => onChanged(
              settings.copyWith(
                dimTextLabel: settings.dimTextLabel.copyWith(fontSize: v),
              ),
            ),
          ),
          _ColorRow(
            label: 'Dim text colour',
            color: settings.dimTextLabel.color,
            onChanged: (c) => onChanged(
              settings.copyWith(
                dimTextLabel: settings.dimTextLabel.copyWith(color: c),
              ),
            ),
          ),
          _WeightRow(
            value: settings.dimTextLabel.fontWeight,
            onChanged: (w) => onChanged(
              settings.copyWith(
                dimTextLabel: settings.dimTextLabel.copyWith(fontWeight: w),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Divider(color: Color(0xFFE2E8F0)),
          const SizedBox(height: 12),
          _SectionHeader('Outside Ruler Dimensions'),
          const SizedBox(height: 10),
          _ToggleRow(
            label: 'Show outside ruler labels',
            value: settings.outsideDimLabel.visible,
            onChanged: (v) => onChanged(
              settings.copyWith(
                outsideDimLabel: settings.outsideDimLabel.copyWith(visible: v),
              ),
            ),
          ),
          _FontSizeSlider(
            value: settings.outsideDimLabel.fontSize,
            min: 7,
            max: 14,
            onChanged: (v) => onChanged(
              settings.copyWith(
                outsideDimLabel: settings.outsideDimLabel.copyWith(fontSize: v),
              ),
            ),
          ),
          _ColorRow(
            label: 'Outside dim colour',
            color: settings.outsideDimLabel.color,
            onChanged: (c) => onChanged(
              settings.copyWith(
                outsideDimLabel: settings.outsideDimLabel.copyWith(color: c),
              ),
            ),
          ),
          _WeightRow(
            value: settings.outsideDimLabel.fontWeight,
            onChanged: (w) => onChanged(
              settings.copyWith(
                outsideDimLabel: settings.outsideDimLabel.copyWith(fontWeight: w),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Divider(color: Color(0xFFE2E8F0)),
          const SizedBox(height: 12),
          _SectionHeader('Arc Labels'),
          const SizedBox(height: 10),
          _ToggleRow(
            label: 'Show arc labels',
            value: settings.arcLabel.visible,
            onChanged: (v) => onChanged(
              settings.copyWith(
                arcLabel: settings.arcLabel.copyWith(visible: v),
              ),
            ),
          ),
          _FontSizeSlider(
            value: settings.arcLabel.fontSize,
            min: 7,
            max: 14,
            onChanged: (v) => onChanged(
              settings.copyWith(
                arcLabel: settings.arcLabel.copyWith(fontSize: v),
              ),
            ),
          ),
          _ColorRow(
            label: 'Arc label colour',
            color: settings.arcLabel.color,
            onChanged: (c) => onChanged(
              settings.copyWith(arcLabel: settings.arcLabel.copyWith(color: c)),
            ),
          ),
          _WeightRow(
            value: settings.arcLabel.fontWeight,
            onChanged: (w) => onChanged(
              settings.copyWith(
                arcLabel: settings.arcLabel.copyWith(fontWeight: w),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab: Canvas Display
// ---------------------------------------------------------------------------

class _CanvasTab extends StatelessWidget {
  const _CanvasTab({required this.settings, required this.onChanged});
  final CanvasDisplaySettings settings;
  final ValueChanged<CanvasDisplaySettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader('Canvas Overlays'),
          const SizedBox(height: 8),
          _ToggleRow(
            label: 'Show grid',
            value: settings.showGrid,
            onChanged: (v) => onChanged(settings.copyWith(showGrid: v)),
          ),
          _ToggleRow(
            label: 'Show profile fill (shaded faces)',
            value: settings.showProfileFill,
            onChanged: (v) => onChanged(settings.copyWith(showProfileFill: v)),
          ),
          _ToggleRow(
            label: 'Show snap points',
            value: settings.showSnapPoints,
            onChanged: (v) => onChanged(settings.copyWith(showSnapPoints: v)),
          ),
          const SizedBox(height: 20),
          _SectionHeader('Geometry'),
          const SizedBox(height: 8),
          _ToggleRow(
            label: 'Show construction geometry',
            value: settings.showConstructionGeometry,
            onChanged: (v) =>
                onChanged(settings.copyWith(showConstructionGeometry: v)),
          ),
          _ToggleRow(
            label: 'Show geometric constraints',
            value: settings.showConstraints,
            onChanged: (v) => onChanged(settings.copyWith(showConstraints: v)),
          ),
          _ToggleRow(
            label: 'Show DOF diagnostics',
            value: settings.showDofDiagnostics,
            onChanged: (v) =>
                onChanged(settings.copyWith(showDofDiagnostics: v)),
          ),
          const SizedBox(height: 20),
          _SectionHeader('Annotations'),
          const SizedBox(height: 8),
          _ToggleRow(
            label: 'Show opening / port tags',
            value: settings.showOpeningTags,
            onChanged: (v) => onChanged(settings.copyWith(showOpeningTags: v)),
          ),
          _ToggleRow(
            label: 'Show all dimension annotations',
            value: settings.showDimensions,
            onChanged: (v) => onChanged(settings.copyWith(showDimensions: v)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared helper widgets
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.bold,
        color: Color(0xFF0F172A),
        letterSpacing: 0.3,
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF334155)),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF334155)),
            ),
          ),
          Switch.adaptive(
            value: value,
            activeThumbColor: const Color(0xFF0369A1),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _FontSizeSlider extends StatelessWidget {
  const _FontSizeSlider({
    required this.value,
    required this.onChanged,
    this.min = 7.0,
    this.max = 16.0,
  });
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Text(
            'Font size',
            style: TextStyle(fontSize: 12.5, color: Color(0xFF334155)),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: ((max - min) * 2).toInt(),
              activeColor: const Color(0xFF0369A1),
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              value.toStringAsFixed(1),
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class _WeightRow extends StatelessWidget {
  const _WeightRow({required this.value, required this.onChanged});
  final FontWeight value;
  final ValueChanged<FontWeight> onChanged;

  @override
  Widget build(BuildContext context) {
    const weights = <FontWeight>[
      FontWeight.w400,
      FontWeight.w500,
      FontWeight.w600,
      FontWeight.bold,
    ];
    const labels = <String>['Normal', 'Medium', 'Semi-bold', 'Bold'];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Text(
            'Font weight',
            style: TextStyle(fontSize: 12.5, color: Color(0xFF334155)),
          ),
          const SizedBox(width: 12),
          ...List.generate(weights.length, (i) {
            final isSelected = value == weights[i];
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => onChanged(weights[i]),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF0369A1)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF0369A1)
                          : const Color(0xFFCBD5E1),
                    ),
                  ),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 11,
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFF475569),
                      fontWeight: weights[i],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({
    required this.label,
    required this.color,
    required this.onChanged,
  });
  final String label;
  final Color color;
  final ValueChanged<Color> onChanged;

  static const _palette = <Color>[
    Color(0xFF0369A1), // Blue
    Color(0xFF6D28D9), // Violet
    Color(0xFF0891B2), // Cyan
    Color(0xFF0F766E), // Teal
    Color(0xFF16A34A), // Green
    Color(0xFFD97706), // Amber
    Color(0xFFDC2626), // Red
    Color(0xFF334155), // Slate
    Color(0xFF475569), // Steel
    Color(0xFF0F172A), // Navy
    Color(0xFF1E3A8A), // Dark Blue
    Color(0xFF065F46), // Dark Green
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF334155)),
          ),
          const SizedBox(width: 12),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: _palette.map((c) {
              final isSelected = c.toARGB32() == color.toARGB32();
              return GestureDetector(
                onTap: () => onChanged(c),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? Colors.white : Colors.transparent,
                      width: 2.5,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: c.withValues(alpha: 0.7),
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions = 20,
    required this.format,
  });
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) format;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF334155)),
            ),
          ),
          Expanded(
            flex: 4,
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              activeColor: const Color(0xFF0369A1),
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(
              format(value),
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewChip extends StatelessWidget {
  const _PreviewChip(this.text, this.bgColor);
  final String text;
  final Color bgColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: bgColor.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1E3A8A),
        ),
      ),
    );
  }
}
