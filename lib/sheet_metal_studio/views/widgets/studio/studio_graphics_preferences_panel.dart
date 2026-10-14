// =============================================================================
// studio_graphics_preferences_panel.dart
//
// Onshape-style CAD Graphics Preferences Panel for TruFold Studio.
// Matches the authentic Onshape Graphics Preferences drawer (Viewport,
// Shaded Bodies, Shininess, Specular Highlights, Line Width, Phantom Edges).
// =============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../models/cad_primitives.dart';
import '../../../viewmodels/sheet_metal_studio_viewmodel.dart';

class StudioGraphicsPreferencesPanel extends StatefulWidget {
  final OnshapeGraphicsPreferences preferences;
  final ValueChanged<OnshapeGraphicsPreferences> onChanged;
  final VoidCallback onClose;
  final VoidCallback onResetToDefault;
  final SheetMetalStudioViewModel? viewModel;
  final double? snapDistancePx;
  final ValueChanged<double>? onSnapDistanceChanged;

  const StudioGraphicsPreferencesPanel({
    super.key,
    required this.preferences,
    required this.onChanged,
    required this.onClose,
    required this.onResetToDefault,
    this.viewModel,
    this.snapDistancePx,
    this.onSnapDistanceChanged,
  });

  @override
  State<StudioGraphicsPreferencesPanel> createState() => _StudioGraphicsPreferencesPanelState();
}

class _StudioGraphicsPreferencesPanelState extends State<StudioGraphicsPreferencesPanel> {
  int _activeTab = 0; // 0 = General, 1 = Sketch
  bool _uiDensityExpanded = true;
  bool _viewportExpanded = true;
  bool _shadedBodiesExpanded = true;
  bool _phantomEdgesExpanded = true;
  bool _lightingExpanded = true;
  bool _materialShaderExpanded = true;
  bool _meshBodiesExpanded = false;

  @override
  Widget build(BuildContext context) {
    final prefs = widget.preferences;
    final screenH = MediaQuery.sizeOf(context).height;

    return Container(
      width: 320,
      constraints: BoxConstraints(maxHeight: math.max(300.0, screenH - 76.0)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 1.0),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Header: "Graphics preferences" with Green Checkmark and Red Close
          _buildHeader(),

          // 2. Tabs: General | Sketch
          _buildTabs(),

          // 3. Scrollable settings body
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Section: UI Scale & Density Setting
                  _buildSectionHeader(
                    title: 'UI Scale & Density',
                    isExpanded: _uiDensityExpanded,
                    onToggle: () => setState(() => _uiDensityExpanded = !_uiDensityExpanded),
                  ),
                  if (_uiDensityExpanded) ...[
                    _buildUiDensitySection(),
                  ],

                  const SizedBox(height: 6),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  const SizedBox(height: 6),

                  // Section: Viewport
                  _buildSectionHeader(
                    title: 'Viewport',
                    isExpanded: _viewportExpanded,
                    onToggle: () => setState(() => _viewportExpanded = !_viewportExpanded),
                  ),
                  if (_viewportExpanded) ...[
                    _buildSliderRow(
                      label: 'Ambient occlusion',
                      valueStr: '${prefs.ambientOcclusion.round()}%',
                      tooltip: 'Controls the contrast of soft ambient shadows in crevices and corners.',
                      value: prefs.ambientOcclusion,
                      min: 0,
                      max: 100,
                      onChanged: (val) => widget.onChanged(prefs.copyWith(ambientOcclusion: val)),
                    ),
                    _buildSliderRow(
                      label: 'Field of view',
                      valueStr: '${prefs.fieldOfView.round()} deg',
                      tooltip: 'Camera angle of view for perspective mode. Lower values approach parallel projection.',
                      value: prefs.fieldOfView,
                      min: 15,
                      max: 90,
                      onChanged: (val) => widget.onChanged(prefs.copyWith(fieldOfView: val)),
                    ),
                    _buildDropdownRow<AntiAliasingQuality>(
                      label: 'Anti-aliasing',
                      value: prefs.antiAliasingQuality,
                      valueLabel: prefs.antiAliasingQuality.label,
                      tooltip: 'Controls hardware MSAA and supersampling anti-aliasing (SSAA) quality in the 3D viewport.',
                      items: AntiAliasingQuality.values.map((q) => PopupMenuItem<AntiAliasingQuality>(
                        value: q,
                        height: 28,
                        child: Text(q.label, style: const TextStyle(fontSize: 11, color: Color(0xFF1E293B))),
                      )).toList(),
                      onSelected: (val) => widget.onChanged(prefs.copyWith(antiAliasingQuality: val)),
                    ),
                    if (widget.onSnapDistanceChanged != null || widget.snapDistancePx != null)
                      _buildSliderRow(
                        label: 'Magnetic snap distance',
                        valueStr: '${(widget.snapDistancePx ?? 10.0).round()} px',
                        tooltip: 'Defines the magnetic attraction distance and strength for snapping to vertices, edges, and centroids.',
                        value: (widget.snapDistancePx ?? 10.0).clamp(4.0, 30.0),
                        min: 4,
                        max: 30,
                        onChanged: (val) => widget.onSnapDistanceChanged?.call(val),
                      ),
                  ],

                  const SizedBox(height: 6),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  const SizedBox(height: 6),

                  // Section: Shaded bodies
                  _buildSectionHeader(
                    title: 'Shaded bodies',
                    isExpanded: _shadedBodiesExpanded,
                    onToggle: () => setState(() => _shadedBodiesExpanded = !_shadedBodiesExpanded),
                  ),
                  if (_shadedBodiesExpanded) ...[
                    _buildSliderRow(
                      label: 'Line width',
                      valueStr: prefs.lineWidth <= 0.05 ? 'Off' : '${prefs.lineWidth.toStringAsFixed(1)} px',
                      tooltip: 'Thickness of visible CAD feature and boundary lines. Slide to 0 to turn borders off.',
                      value: prefs.lineWidth,
                      min: 0.0,
                      max: 4.0,
                      onChanged: (val) => widget.onChanged(prefs.copyWith(lineWidth: val <= 0.05 ? 0.0 : val)),
                    ),
                    _buildSliderRow(
                      label: 'Shininess',
                      valueStr: '${prefs.shininess.round()}%',
                      tooltip: 'Change the shininess of shaded surfaces (specular reflectivity).',
                      value: prefs.shininess,
                      min: 0,
                      max: 100,
                      onChanged: (val) => widget.onChanged(prefs.copyWith(shininess: val)),
                    ),
                    _buildColorRow(
                      label: 'Specular color',
                      color: prefs.specularColor,
                      tooltip: 'Color of the glossy specular light highlight.',
                      onSelect: (c) => widget.onChanged(prefs.copyWith(specularColor: c)),
                    ),
                    _buildColorRow(
                      label: 'Section interference color',
                      color: prefs.sectionInterferenceColor,
                      tooltip: 'Color used for highlighting section interference cuts.',
                      onSelect: (c) => widget.onChanged(prefs.copyWith(sectionInterferenceColor: c)),
                    ),
                    _buildToggleRow(
                      label: 'Highlight boundary edges',
                      value: prefs.highlightBoundaryEdges,
                      tooltip: 'Visually highlight open boundary edges (sheet metal edges, open boundaries) with an accent color.',
                      onChanged: (val) => widget.onChanged(prefs.copyWith(highlightBoundaryEdges: val)),
                    ),
                    if (prefs.highlightBoundaryEdges)
                      _buildColorRow(
                        label: 'Boundary edge color',
                        color: prefs.boundaryEdgeColor,
                        tooltip: 'Color used for highlighted boundary edges.',
                        onSelect: (c) => widget.onChanged(prefs.copyWith(boundaryEdgeColor: c)),
                      ),
                    _buildSliderRow(
                      label: 'Translucent opacity',
                      valueStr: '${(prefs.transparencyLevel * 100).round()}%',
                      tooltip: 'Opacity percentage for parts or faces rendered in translucent mode.',
                      value: prefs.transparencyLevel,
                      min: 0.05,
                      max: 0.95,
                      onChanged: (val) => widget.onChanged(prefs.copyWith(transparencyLevel: val)),
                    ),
                  ],

                  const SizedBox(height: 6),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  const SizedBox(height: 6),

                  // Section: Phantom edges
                  _buildSectionHeader(
                    title: 'Phantom edges',
                    isExpanded: _phantomEdgesExpanded,
                    onToggle: () => setState(() => _phantomEdgesExpanded = !_phantomEdgesExpanded),
                  ),
                  if (_phantomEdgesExpanded) ...[
                    _buildDropdownRow<OnshapeTangentEdgeMode>(
                      label: 'Tangent edge display',
                      value: prefs.tangentEdgeMode,
                      valueLabel: prefs.tangentEdgeMode.label,
                      tooltip: 'Controls how blend/fillet tangent edges are rendered (Visible solid, Phantom dashed, or Removed).',
                      items: OnshapeTangentEdgeMode.values.map((mode) => PopupMenuItem<OnshapeTangentEdgeMode>(
                        value: mode,
                        height: 28,
                        child: Text(mode.label, style: const TextStyle(fontSize: 11, color: Color(0xFF1E293B))),
                      )).toList(),
                      onSelected: (val) => widget.onChanged(prefs.copyWith(tangentEdgeMode: val)),
                    ),
                    _buildSliderRow(
                      label: 'Phantom tangent edge width',
                      valueStr: '${prefs.phantomTangentEdgeWidth.toStringAsFixed(1)} px',
                      tooltip: 'Thickness of hidden and phantom tangent edges.',
                      value: prefs.phantomTangentEdgeWidth,
                      min: 0.5,
                      max: 4.0,
                      onChanged: (val) => widget.onChanged(prefs.copyWith(phantomTangentEdgeWidth: val)),
                    ),
                    _buildColorRow(
                      label: 'Phantom tangent edge color',
                      color: prefs.phantomTangentEdgeColor,
                      tooltip: 'Color of phantom and hidden edge line segments.',
                      onSelect: (c) => widget.onChanged(prefs.copyWith(phantomTangentEdgeColor: c)),
                    ),
                  ],

                  const SizedBox(height: 6),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  const SizedBox(height: 6),

                  // Section: Studio Lighting
                  _buildSectionHeader(
                    title: 'Studio lighting',
                    isExpanded: _lightingExpanded,
                    onToggle: () => setState(() => _lightingExpanded = !_lightingExpanded),
                  ),
                  if (_lightingExpanded) ...[
                    _buildSliderRow(
                      label: 'Light azimuth',
                      valueStr: '${prefs.lightAzimuthDeg.round()} deg',
                      tooltip: 'Rotates the key light horizontally around the 3D model.',
                      value: prefs.lightAzimuthDeg,
                      min: 0,
                      max: 360,
                      onChanged: (val) => widget.onChanged(prefs.copyWith(lightAzimuthDeg: val)),
                    ),
                    _buildSliderRow(
                      label: 'Light elevation',
                      valueStr: '${prefs.lightElevationDeg.round()} deg',
                      tooltip: 'Tilts the key light angle up from horizontal to zenith.',
                      value: prefs.lightElevationDeg,
                      min: 10,
                      max: 90,
                      onChanged: (val) => widget.onChanged(prefs.copyWith(lightElevationDeg: val)),
                    ),
                    _buildSliderRow(
                      label: 'Key intensity',
                      valueStr: prefs.keyLightIntensity.toStringAsFixed(2),
                      tooltip: 'Brightness of the primary spotlight creating highlights.',
                      value: prefs.keyLightIntensity,
                      min: 0.0,
                      max: 3.0,
                      onChanged: (val) => widget.onChanged(prefs.copyWith(keyLightIntensity: val)),
                    ),
                    _buildToggleRow(
                      label: 'Secondary fill light',
                      value: prefs.hasSecondaryLight,
                      tooltip: 'Soft ambient fill light from opposite angle to brighten shadows.',
                      onChanged: (val) => widget.onChanged(prefs.copyWith(hasSecondaryLight: val)),
                    ),
                    _buildToggleRow(
                      label: 'Rim / back light',
                      value: prefs.hasBackLight,
                      tooltip: 'Backlight behind the model creating sharp edge silhouettes.',
                      onChanged: (val) => widget.onChanged(prefs.copyWith(hasBackLight: val)),
                    ),
                  ],

                  const SizedBox(height: 6),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  const SizedBox(height: 6),

                  // Section: Material / Shader (Procedural PBR & Voronoi HDG Spangle)
                  _buildSectionHeader(
                    title: 'Material / Shader',
                    isExpanded: _materialShaderExpanded,
                    onToggle: () => setState(() => _materialShaderExpanded = !_materialShaderExpanded),
                  ),
                  if (_materialShaderExpanded) ...[
                    _buildMaterialShaderSection(prefs),
                  ],

                  const SizedBox(height: 6),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  const SizedBox(height: 6),

                  // Section: Mesh bodies (collapsed placeholder)
                  _buildSectionHeader(
                    title: 'Mesh bodies',
                    isExpanded: _meshBodiesExpanded,
                    onToggle: () => setState(() => _meshBodiesExpanded = !_meshBodiesExpanded),
                  ),
                  if (_meshBodiesExpanded) ...[
                    _buildSliderRow(
                      label: 'Mesh line width',
                      valueStr: prefs.meshLineWidth <= 0.05 ? 'Off' : '${prefs.meshLineWidth.toStringAsFixed(1)} px',
                      tooltip: 'Thickness of mesh polygon wireframes and tessellation borders.',
                      value: prefs.meshLineWidth,
                      min: 0.0,
                      max: 4.0,
                      onChanged: (val) => widget.onChanged(prefs.copyWith(meshLineWidth: val <= 0.05 ? 0.0 : val)),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // 4. Footer: Reset to default button and Help icon
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(6),
          topRight: Radius.circular(6),
        ),
        border: Border(
          bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1.0),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Expanded(
            child: Text(
              'Graphics preferences',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Row(
            children: [
              // Green Checkmark Button
              InkWell(
                onTap: widget.onClose,
                borderRadius: BorderRadius.circular(3),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: const Color(0xFF16A34A),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Icon(
                    Icons.check,
                    color: Colors.white,
                    size: 15,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Red Close Button
              InkWell(
                onTap: widget.onClose,
                borderRadius: BorderRadius.circular(3),
                child: const SizedBox(
                  width: 20,
                  height: 20,
                  child: Icon(
                    Icons.close,
                    color: Color(0xFFEF4444),
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF1F5F9),
        border: Border(
          bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1.0),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _activeTab = 0),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: _activeTab == 0 ? const Color(0xFF0284C7) : Colors.transparent,
                      width: 2.0,
                    ),
                  ),
                ),
                child: Text(
                  'General',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: _activeTab == 0 ? FontWeight.bold : FontWeight.w500,
                    color: _activeTab == 0 ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _activeTab = 1),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: _activeTab == 1 ? const Color(0xFF0284C7) : Colors.transparent,
                      width: 2.0,
                    ),
                  ),
                ),
                child: Text(
                  'Sketch',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: _activeTab == 1 ? FontWeight.bold : FontWeight.w500,
                    color: _activeTab == 1 ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required bool isExpanded,
    required VoidCallback onToggle,
  }) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          children: [
            Icon(
              isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
              size: 16,
              color: const Color(0xFF475569),
            ),
            const SizedBox(width: 4),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF334155),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliderRow({
    required String label,
    required String valueStr,
    required String tooltip,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Row(
                children: [
                  Text(
                    valueStr,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: tooltip,
                    child: const Icon(
                      Icons.info_outline,
                      size: 13,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: const Color(0xFF0284C7),
              inactiveTrackColor: const Color(0xFFE2E8F0),
              thumbColor: const Color(0xFF0284C7),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorRow({
    required String label,
    required Color color,
    required String tooltip,
    required ValueChanged<Color> onSelect,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 6, bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PopupMenuButton<Color>(
                tooltip: 'Select $label',
                padding: EdgeInsets.zero,
                itemBuilder: (context) => [
                  Colors.white,
                  const Color(0xFFE0E0E0),
                  const Color(0xFFB0BEC5),
                  const Color(0xFF70A5C2),
                  const Color(0xFF4CAF50),
                  const Color(0xFFEF4444),
                  const Color(0xFF212121),
                ].map((c) {
                  return PopupMenuItem<Color>(
                    value: c,
                    height: 32,
                    child: Container(
                      height: 20,
                      decoration: BoxDecoration(
                        color: c,
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                    ),
                  );
                }).toList(),
                onSelected: onSelect,
                child: Container(
                  width: 32,
                  height: 18,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: const Color(0xFF94A3B8), width: 1.0),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: tooltip,
                child: const Icon(
                  Icons.info_outline,
                  size: 13,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownRow<T>({
    required String label,
    required T value,
    required String valueLabel,
    required List<PopupMenuEntry<T>> items,
    required ValueChanged<T> onSelected,
    required String tooltip,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PopupMenuButton<T>(
                initialValue: value,
                itemBuilder: (context) => items,
                onSelected: onSelected,
                child: Container(
                  height: 22,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                    color: const Color(0xFFF8FAFC),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        valueLabel,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF1E293B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_drop_down, size: 14, color: Color(0xFF64748B)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: tooltip,
                child: const Icon(
                  Icons.info_outline,
                  size: 13,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToggleRow({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    required String tooltip,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 20,
                width: 34,
                child: Switch(
                  value: value,
                  onChanged: onChanged,
                  activeThumbColor: const Color(0xFF0284C7),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: tooltip,
                child: const Icon(
                  Icons.info_outline,
                  size: 13,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMaterialShaderSection(OnshapeGraphicsPreferences prefs) {
    final mat = prefs.materialSettings;

    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Preset Dropdown
          _buildDropdownRow<CadMaterialPresetType>(
            label: 'Material preset',
            value: mat.preset,
            valueLabel: mat.preset.label,
            tooltip: 'Selects high-performance PBR or procedural shader material (HDG, PGI, Plastic, Metals)',
            items: CadMaterialPresetType.values
                .map((p) => PopupMenuItem<CadMaterialPresetType>(
                      value: p,
                      height: 28,
                      child: Text(
                        p.label,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF1E293B)),
                      ),
                    ))
                .toList(),
            onSelected: (val) {
              widget.onChanged(prefs.copyWith(
                materialSettings: CadMaterialSettings.preset(val),
              ));
            },
          ),

          // 2. Roughness Slider
          _buildSliderRow(
            label: 'Roughness factor',
            valueStr: mat.roughness.toStringAsFixed(2),
            tooltip: 'Microfacet surface roughness: lower is mirror-sharp, higher is diffuse-matte.',
            value: mat.roughness,
            min: 0.04,
            max: 1.0,
            onChanged: (val) => widget.onChanged(prefs.copyWith(
              materialSettings: mat.copyWith(roughness: val),
            )),
          ),

          // 3. Dielectric (Plastic) vs Conductor (Metal) indicator & toggle
          _buildToggleRow(
            label: 'Dielectric / Plastic (0.0 metallic)',
            value: mat.isPlastic,
            tooltip: 'Sets metallic factor to 0.0 for non-metal dielectrics (plastics) or 1.0 for metals.',
            onChanged: (val) => widget.onChanged(prefs.copyWith(
              materialSettings: mat.copyWith(isPlastic: val),
            )),
          ),

          // 4. Custom Pigment & Universal RAL Swatches (for Paint, Plastic, or Custom)
          if (mat.isPlastic || mat.preset == CadMaterialPresetType.custom || mat.preset == CadMaterialPresetType.paint) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        mat.preset == CadMaterialPresetType.paint ? 'Universal RAL Coat:' : 'Pigment tint:',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
                      ),
                      const SizedBox(width: 6),
                      if (mat.preset == CadMaterialPresetType.paint) ...[
                        PopupMenuButton<RalColor>(
                          tooltip: 'Select RAL Classic Color',
                          onSelected: (ral) {
                            widget.onChanged(prefs.copyWith(
                              materialSettings: mat.copyWith(baseColor: ral.color),
                            ));
                          },
                          itemBuilder: (ctx) => [
                            for (final c in RalColor.topCMSColors)
                              PopupMenuItem(
                                value: c,
                                height: 26,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: c.color,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.black26, width: 0.5),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(c.displayName, style: const TextStyle(fontSize: 10.5, color: Color(0xFF1E293B))),
                                  ],
                                ),
                              ),
                          ],
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(color: const Color(0xFF0284C7), width: 0.8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: mat.baseColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Text('RAL Chart', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF0284C7))),
                                const Icon(Icons.arrow_drop_down, size: 14, color: Color(0xFF0284C7)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 6,
                    children: (mat.preset == CadMaterialPresetType.paint
                            ? RalColor.topCMSColors.map((r) => r.color).toList()
                            : const [
                                Color(0xFF1E88E5), // Blue
                                Color(0xFFE53935), // Red
                                Color(0xFF43A047), // Green
                                Color(0xFFFB8C00), // Orange
                                Color(0xFF8E24AA), // Purple
                                Color(0xFF263238), // Dark Slate
                                Color(0xFFF5F5F5), // White
                              ])
                        .map((color) {
                      final isSelected = mat.baseColor.toARGB32() == color.toARGB32();
                      return InkWell(
                        onTap: () => widget.onChanged(prefs.copyWith(
                          materialSettings: mat.copyWith(baseColor: color),
                        )),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1),
                              width: isSelected ? 2.5 : 1.0,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 6),

          // 5. Procedural HDG Spangle Pipeline Execution Card
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: mat.useSpangles ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: mat.useSpangles ? const Color(0xFF86EFAC) : const Color(0xFFE2E8F0),
                width: 1.0,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.grain,
                          size: 15,
                          color: mat.useSpangles ? const Color(0xFF15803D) : const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Procedural HDG Spangles',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: mat.useSpangles ? const Color(0xFF166534) : const Color(0xFF475569),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(
                      height: 20,
                      width: 34,
                      child: Switch(
                        value: mat.useSpangles,
                        activeThumbColor: const Color(0xFF16A34A),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onChanged: (active) {
                          widget.onChanged(prefs.copyWith(
                            materialSettings: mat.copyWith(useSpangles: active),
                          ));
                        },
                      ),
                    ),
                  ],
                ),
                if (mat.useSpangles) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Zinc crystal density (scale)',
                        style: TextStyle(fontSize: 10, color: Color(0xFF475569)),
                      ),
                      Text(
                        mat.spangleScale.toStringAsFixed(0),
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF166534)),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                      trackHeight: 2,
                    ),
                    child: Slider(
                      value: mat.spangleScale.clamp(10.0, 100.0),
                      min: 10.0,
                      max: 100.0,
                      activeColor: const Color(0xFF16A34A),
                      inactiveColor: const Color(0xFFDCFCE7),
                      onChanged: (val) {
                        widget.onChanged(prefs.copyWith(
                          materialSettings: mat.copyWith(spangleScale: val),
                        ));
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),

          // 3D Welding Seam Overlay Setting (SS1 / SS2)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: prefs.showWeldOverlay ? const Color(0xFFFEF3C7) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: prefs.showWeldOverlay ? const Color(0xFFF59E0B) : const Color(0xFFE2E8F0)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.blur_linear_rounded,
                      size: 15,
                      color: prefs.showWeldOverlay ? const Color(0xFFD97706) : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Translucent Weld Overlay',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: prefs.showWeldOverlay ? const Color(0xFF92400E) : const Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
                SizedBox(
                  height: 20,
                  width: 34,
                  child: Switch(
                    value: prefs.showWeldOverlay,
                    activeThumbColor: const Color(0xFFD97706),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (active) {
                      widget.onChanged(prefs.copyWith(showWeldOverlay: active));
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(6),
          bottomRight: Radius.circular(6),
        ),
        border: Border(
          top: BorderSide(color: Color(0xFFE2E8F0), width: 1.0),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          OutlinedButton(
            onPressed: widget.onResetToDefault,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.0),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            child: const Text(
              'Reset to default',
              style: TextStyle(fontSize: 11, color: Color(0xFF475569)),
            ),
          ),
          Tooltip(
            message: 'Help & Documentation on Graphics Preferences',
            child: InkWell(
              onTap: () {},
              borderRadius: BorderRadius.circular(10),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(
                  Icons.help_outline,
                  size: 16,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUiDensitySection() {
    final vm = widget.viewModel;
    final currentMode = vm?.uiDensityMode ?? UiDensityMode.auto;
    final scale = vm?.uiScaleFactor ?? 0.85;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Density Preset', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Active: ${(scale * 100).toInt()}% Scale',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final mode in UiDensityMode.values) ...[
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2.0),
                    child: InkWell(
                      onTap: () {
                        if (vm != null) {
                          vm.setUiDensityMode(mode);
                          setState(() {});
                        }
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: currentMode == mode ? const Color(0xFFE0F2FE) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: currentMode == mode ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1),
                            width: currentMode == mode ? 1.2 : 0.8,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              mode.icon,
                              size: 14,
                              color: currentMode == mode ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              mode.label,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: currentMode == mode ? FontWeight.bold : FontWeight.normal,
                                color: currentMode == mode ? const Color(0xFF0284C7) : const Color(0xFF475569),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            currentMode == UiDensityMode.auto
                ? '• Auto: Automatically switches to Compact (85%) when screen width < 1600px.'
                : (currentMode == UiDensityMode.compact
                    ? '• Compact (85%): Scales down icons (24->18px), buttons, and paddings for laptops.'
                    : '• Standard (100%): Full-size layout for large desktop monitors (> 24").'),
            style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }
}
