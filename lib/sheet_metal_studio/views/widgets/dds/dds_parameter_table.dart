// =============================================================================
// dds_parameter_table.dart
//
// Technical Data Sheet (TDS) Tabular Parameter Editor Widget.
// Displays and edits client-facing product parameters for a DdsProductInstance.
//
// Complies with Spec Sections 12, 37 & 38:
// 1. Clearly separates:
//    - DDS instance value / editable
//    - Template-defined / read-only
//    - Derived value / calculated
// 2. Supports live parameter morphing with real-time onInstanceChanged callback.
// 3. Displays physical takeoff (blank area m², estimated net weight kg).
// 4. Professional engineering styling suitable for technical submittal review.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../engine/dds/dds_instance_evaluator.dart';
import '../../../models/dds/dds_product_instance.dart';

enum ParameterSource {
  ddsEditable,
  templateFixed,
  derivedCalculated,
}

class DdsParameterItem {
  final String key;
  final String label;
  final String symbol;
  final double? numValue;
  final String? strValue;
  final String unit;
  final ParameterSource source;
  final double minValue;
  final double maxValue;
  final bool isNumeric;

  const DdsParameterItem({
    required this.key,
    required this.label,
    this.symbol = '',
    this.numValue,
    this.strValue,
    this.unit = 'mm',
    this.source = ParameterSource.ddsEditable,
    this.minValue = 10.0,
    this.maxValue = 2500.0,
    this.isNumeric = true,
  });
}

class DdsParameterTable extends StatefulWidget {
  final DdsProductInstance instance;
  final ValueChanged<DdsProductInstance> onInstanceChanged;
  final bool isReadOnly;

  const DdsParameterTable({
    super.key,
    required this.instance,
    required this.onInstanceChanged,
    this.isReadOnly = false,
  });

  @override
  State<DdsParameterTable> createState() => _DdsParameterTableState();
}

class _DdsParameterTableState extends State<DdsParameterTable> {
  late Map<String, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = {};
    _syncControllers();
  }

  @override
  void didUpdateWidget(covariant DdsParameterTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.instance != widget.instance) {
      _syncControllers();
    }
  }

  void _syncControllers() {
    final items = _buildParameterList();
    for (final item in items) {
      if (item.isNumeric && item.numValue != null) {
        final text = item.numValue! % 1 == 0
            ? item.numValue!.toInt().toString()
            : item.numValue!.toStringAsFixed(1);
        if (_controllers.containsKey(item.key)) {
          if (_controllers[item.key]!.text != text) {
            _controllers[item.key]!.text = text;
          }
        } else {
          _controllers[item.key] = TextEditingController(text: text);
        }
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<DdsParameterItem> _buildParameterList() {
    final p = widget.instance.instanceParameters;
    final tId = widget.instance.templateReference.templateId.toLowerCase();
    final items = <DdsParameterItem>[];

    if (tId.contains('reducer')) {
      items.add(DdsParameterItem(
        key: 'port1_width',
        label: 'Inlet Width',
        symbol: 'W₁',
        numValue: p['port1_width'] ?? 100.0,
        unit: 'mm',
      ));
      items.add(DdsParameterItem(
        key: 'port1_height',
        label: 'Inlet Height',
        symbol: 'H₁',
        numValue: p['port1_height'] ?? 100.0,
        unit: 'mm',
      ));
      items.add(DdsParameterItem(
        key: 'port2_width',
        label: 'Outlet Width',
        symbol: 'W₂',
        numValue: p['port2_width'] ?? 50.0,
        unit: 'mm',
      ));
      items.add(DdsParameterItem(
        key: 'port2_height',
        label: 'Outlet Height',
        symbol: 'H₂',
        numValue: p['port2_height'] ?? 50.0,
        unit: 'mm',
      ));
      items.add(const DdsParameterItem(
        key: 'coupler_flange',
        label: 'Coupler Flange Lip',
        symbol: 'F',
        numValue: 15.0,
        unit: 'mm',
        source: ParameterSource.templateFixed,
      ));
    } else if (tId.contains('tee')) {
      final isUnequal = tId.contains('unequal');
      items.add(DdsParameterItem(
        key: isUnequal ? 'port1_width' : 'width',
        label: 'Main Trunk Width',
        symbol: 'W',
        numValue: p['port1_width'] ?? p['width'] ?? 100.0,
        unit: 'mm',
      ));
      items.add(DdsParameterItem(
        key: isUnequal ? 'port1_height' : 'height',
        label: 'Main Trunk Height',
        symbol: 'H',
        numValue: p['port1_height'] ?? p['height'] ?? 100.0,
        unit: 'mm',
      ));
      if (isUnequal) {
        items.add(DdsParameterItem(
          key: 'port3_width',
          label: 'Branch Width',
          symbol: 'W_br',
          numValue: p['port3_width'] ?? p['branch_width'] ?? 50.0,
          unit: 'mm',
        ));
        items.add(DdsParameterItem(
          key: 'port3_height',
          label: 'Branch Height',
          symbol: 'H_br',
          numValue: p['port3_height'] ?? p['branch_height'] ?? 50.0,
          unit: 'mm',
        ));
      }
      items.add(const DdsParameterItem(
        key: 'gusset_radius',
        label: 'Gusset Radius',
        symbol: 'R',
        numValue: 50.0,
        unit: 'mm',
        source: ParameterSource.templateFixed,
      ));
    } else {
      // Bends, Risers, Crosses, Generic
      items.add(DdsParameterItem(
        key: 'width',
        label: 'Trunking Width',
        symbol: 'W',
        numValue: p['width'] ?? p['port1_width'] ?? 100.0,
        unit: 'mm',
      ));
      items.add(DdsParameterItem(
        key: 'height',
        label: 'Trunking Height',
        symbol: 'H',
        numValue: p['height'] ?? p['port1_height'] ?? 100.0,
        unit: 'mm',
      ));
      if (tId.contains('45')) {
        items.add(const DdsParameterItem(
          key: 'angle',
          label: 'Deflection Angle',
          symbol: 'θ',
          numValue: 45.0,
          unit: '°',
          source: ParameterSource.templateFixed,
        ));
      } else {
        items.add(const DdsParameterItem(
          key: 'angle',
          label: 'Deflection Angle',
          symbol: 'θ',
          numValue: 90.0,
          unit: '°',
          source: ParameterSource.templateFixed,
        ));
      }
      if (tId.contains('bend')) {
        items.add(DdsParameterItem(
          key: 'radius',
          label: 'Bend Radius',
          symbol: 'R',
          numValue: p['radius'] ?? 180.0,
          unit: 'mm',
          minValue: 180.0,
          maxValue: 900.0,
          source: ParameterSource.ddsEditable,
        ));
      }
    }

    return items;
  }

  void _onNumberChanged(String key, String text, double min, double max) {
    final parsed = double.tryParse(text);
    if (parsed == null || parsed < min || parsed > max) return;

    final updatedParams = Map<String, double>.from(widget.instance.instanceParameters);
    updatedParams[key] = parsed;

    // Synchronize symmetric or alias parameters
    if (key == 'width') {
      updatedParams['port1_width'] = parsed;
    } else if (key == 'height') {
      updatedParams['port1_height'] = parsed;
    } else if (key == 'radius') {
      updatedParams['radius'] = parsed;
    }

    final updatedInstance = widget.instance.copyWith(
      instanceParameters: updatedParams,
    );

    widget.onInstanceChanged(updatedInstance);
  }

  void _onCoverToggle(bool value) {
    final updatedCover = widget.instance.coverConfiguration.copyWith(
      included: value,
    );
    widget.onInstanceChanged(widget.instance.copyWith(coverConfiguration: updatedCover));
  }

  void _onCoverPlacementChanged(String mode) {
    final updatedCover = widget.instance.coverConfiguration.copyWith(
      placementMode3D: mode,
    );
    widget.onInstanceChanged(widget.instance.copyWith(coverConfiguration: updatedCover));
  }

  @override
  Widget build(BuildContext context) {
    final items = _buildParameterList();
    final takeoff = widget.instance.calculatedTakeoff;
    final density = DdsInstanceEvaluator.resolveDensity(widget.instance.material);
    final thk = ((widget.instance.instanceParameters['thickness'] ?? 1.5) as num).toDouble();
    final double? netMass = takeoff != null && takeoff.blankSurfaceAreaM2 > 0
        ? (takeoff.blankSurfaceAreaM2 * (thk / 1000.0) * density)
        : takeoff?.estimatedNetWeightKg;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A), // Slate 900
        borderRadius: BorderRadius.circular(10.0),
        border: Border.all(color: const Color(0xFF334155), width: 1.0), // Slate 700
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar
          _buildHeaderBar(),
          const Divider(height: 1, color: Color(0xFF334155)),

          // Scrollable Parameter Rows
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
              children: [
                // Group 1: Engineering Geometry
                _buildSectionHeader(Icons.straighten, 'GEOMETRIC DIMENSIONS'),
                const SizedBox(height: 6.0),
                ...items.map((item) => _buildParameterRow(item)),

                const SizedBox(height: 16.0),
                // Group 2: Live Cover Configuration
                _buildSectionHeader(Icons.layers_outlined, 'PARAMETRIC COVER (LIVE)'),
                const SizedBox(height: 6.0),
                _buildCoverSection(),

                const SizedBox(height: 16.0),
                // Group 3: Material & Specification
                _buildSectionHeader(Icons.shield_outlined, 'SPECIFICATION & MATERIAL'),
                const SizedBox(height: 6.0),
                _buildMaterialRow('Material', widget.instance.material),
                _buildMaterialRow('Finish', widget.instance.finish),

                const SizedBox(height: 16.0),
                // Group 4: Physical Takeoff
                _buildSectionHeader(Icons.calculate_outlined, 'PHYSICAL TAKEOFF (CALCULATED)'),
                const SizedBox(height: 6.0),
                _buildTakeoffRow(
                  label: 'Blank Surface Area',
                  value: takeoff != null ? '${takeoff.blankSurfaceAreaM2.toStringAsFixed(3)} m²' : '—',
                ),
                _buildTakeoffRow(
                  label: 'Estimated Net Mass',
                  value: netMass != null ? '${netMass.toStringAsFixed(2)} kg' : '—',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderBar() {
    final order = widget.instance.orderLine;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B), // Slate 800
        borderRadius: BorderRadius.vertical(top: Radius.circular(9.0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6.0),
            decoration: BoxDecoration(
              color: const Color(0xFF0284C7).withValues(alpha: 0.2), // Sky blue tint
              borderRadius: BorderRadius.circular(6.0),
            ),
            child: const Icon(Icons.tune, color: Color(0xFF38BDF8), size: 18),
          ),
          const SizedBox(width: 10.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.instance.productName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.0,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (order != null)
                  Text(
                    'Line ${order.lineNumber} • Ref: ${order.customerItemReference} • Qty: ${order.quantity}',
                    style: const TextStyle(
                      color: Color(0xFF94A3B8), // Slate 400
                      fontSize: 11.0,
                    ),
                  ),
              ],
            ),
          ),
          _buildSourceBadge(ParameterSource.ddsEditable),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF94A3B8)),
        const SizedBox(width: 6.0),
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 11.0,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }

  Widget _buildParameterRow(DdsParameterItem item) {
    final isEditable = item.source == ParameterSource.ddsEditable && !widget.isReadOnly;

    return Container(
      margin: const EdgeInsets.only(bottom: 6.0),
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(6.0),
        border: Border.all(color: const Color(0xFF334155), width: 0.8),
      ),
      child: Row(
        children: [
          // Symbol Pill
          if (item.symbol.isNotEmpty)
            Container(
              width: 32,
              padding: const EdgeInsets.symmetric(vertical: 2.0),
              decoration: BoxDecoration(
                color: const Color(0xFF334155),
                borderRadius: BorderRadius.circular(4.0),
              ),
              alignment: Alignment.center,
              child: Text(
                item.symbol,
                style: const TextStyle(
                  color: Color(0xFF38BDF8),
                  fontSize: 11.0,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          const SizedBox(width: 8.0),

          // Label
          Expanded(
            child: Text(
              item.label,
              style: const TextStyle(
                color: Color(0xFFCBD5E1), // Slate 300
                fontSize: 12.0,
              ),
            ),
          ),

          // Value Field
          if (isEditable && item.isNumeric)
            SizedBox(
              width: 70,
              height: 28,
              child: TextField(
                controller: _controllers[item.key],
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.white, fontSize: 12.0, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
                  filled: true,
                  fillColor: const Color(0xFF0F172A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4.0),
                    borderSide: const BorderSide(color: Color(0xFF475569)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4.0),
                    borderSide: const BorderSide(color: Color(0xFF38BDF8)),
                  ),
                ),
                onSubmitted: (val) => _onNumberChanged(item.key, val, item.minValue, item.maxValue),
              ),
            )
          else
            Text(
              item.numValue != null
                  ? (item.numValue! % 1 == 0 ? item.numValue!.toInt().toString() : item.numValue!.toStringAsFixed(1))
                  : (item.strValue ?? '—'),
              style: TextStyle(
                color: isEditable ? Colors.white : const Color(0xFF94A3B8),
                fontSize: 12.0,
                fontWeight: FontWeight.w600,
              ),
            ),

          const SizedBox(width: 6.0),
          // Unit
          SizedBox(
            width: 24,
            child: Text(
              item.unit,
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 11.0),
            ),
          ),
          const SizedBox(width: 6.0),

          // Source Badge
          _buildSourceBadge(item.source),
        ],
      ),
    );
  }

  Widget _buildCoverSection() {
    final cover = widget.instance.coverConfiguration;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(6.0),
        border: Border.all(color: const Color(0xFF334155), width: 0.8),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Include Cover in Submittal',
                style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 12.0),
              ),
              Switch(
                value: cover.included,
                activeThumbColor: const Color(0xFF38BDF8),
                activeTrackColor: const Color(0xFF0369A1),
                inactiveThumbColor: const Color(0xFF64748B),
                inactiveTrackColor: const Color(0xFF334155),
                onChanged: widget.isReadOnly ? null : _onCoverToggle,
              ),
            ],
          ),
          if (cover.included) ...[
            const SizedBox(height: 6.0),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '3D Presentation Mode',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.0),
                ),
                DropdownButton<String>(
                  value: cover.placementMode3D,
                  dropdownColor: const Color(0xFF1E293B),
                  style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12.0),
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 'exploded', child: Text('Exploded (Hovering)')),
                    DropdownMenuItem(value: 'snappedToBase', child: Text('Snapped to Base')),
                    DropdownMenuItem(value: 'besideBase', child: Text('Beside Base')),
                  ],
                  onChanged: widget.isReadOnly ? null : (val) => val != null ? _onCoverPlacementChanged(val) : null,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMaterialRow(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6.0),
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(6.0),
        border: Border.all(color: const Color(0xFF334155), width: 0.8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12.0)),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 12.0, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildTakeoffRow({required String label, required String value}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6.0),
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(6.0),
        border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.4), width: 1.0),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12.0)),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF38BDF8),
              fontSize: 13.0,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceBadge(ParameterSource source) {
    String text;
    Color bg;
    Color fg;

    switch (source) {
      case ParameterSource.ddsEditable:
        text = 'DDS';
        bg = const Color(0xFF0284C7).withValues(alpha: 0.2);
        fg = const Color(0xFF38BDF8);
        break;
      case ParameterSource.templateFixed:
        text = 'TEMPLATE';
        bg = const Color(0xFF334155);
        fg = const Color(0xFF94A3B8);
        break;
      case ParameterSource.derivedCalculated:
        text = 'DERIVED';
        bg = const Color(0xFFF59E0B).withValues(alpha: 0.2);
        fg = const Color(0xFFFBBF24);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4.0),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg,
          fontSize: 9.0,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
