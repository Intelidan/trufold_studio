// =============================================================================
// template_library_gallery_dialog.dart
//
// Visual catalog gallery and parametric inspector for pre-bundled factory
// presets and authored templates (SET 13 & 23, Phase 1 Master Guide).
// =============================================================================

import 'package:flutter/material.dart';
import '../../models/template_parameter_definition.dart';
import '../../viewmodels/sheet_metal_studio_viewmodel.dart';
import 'template_authoring_wizard_dialog.dart';

class TemplateLibraryGalleryDialog extends StatefulWidget {
  final SheetMetalStudioViewModel? viewModel;
  final void Function(TemplateParameterDefinition template, Map<String, double> parameters)?
      onInstantiate;

  const TemplateLibraryGalleryDialog({
    super.key,
    this.viewModel,
    this.onInstantiate,
  });

  @override
  State<TemplateLibraryGalleryDialog> createState() =>
      _TemplateLibraryGalleryDialogState();
}

class _TemplateCatalogEntry {
  final String id;
  final String name;
  final String category;
  final String productCode;
  final String description;
  final TemplateParameterDefinition template;
  final Map<String, double> defaultDimensions;

  const _TemplateCatalogEntry({
    required this.id,
    required this.name,
    required this.category,
    required this.productCode,
    required this.description,
    required this.template,
    required this.defaultDimensions,
  });
}

class _TemplateLibraryGalleryDialogState
    extends State<TemplateLibraryGalleryDialog> {
  String _selectedCategory = 'All';
  String _searchQuery = '';
  late List<_TemplateCatalogEntry> _catalog;
  _TemplateCatalogEntry? _selectedEntry;
  final Map<String, double> _liveParameters = {};

  @override
  void initState() {
    super.initState();
    _initCatalog();
    if (_catalog.isNotEmpty) {
      _selectEntry(_catalog.first);
    }
  }

  void _initCatalog() {
    _catalog = [
      _TemplateCatalogEntry(
        id: 'CT_STRAIGHT',
        name: 'Straight Cable Tray',
        category: 'Cable Trays',
        productCode: 'CT-100x50x3000',
        description: 'Standard heavy-duty perforated straight cable tray section.',
        template: TemplateParameterDefinition.cableTrayStraight(width: 100, height: 50, length: 1000),
        defaultDimensions: {'width': 100.0, 'height': 50.0, 'length': 1000.0},
      ),
      _TemplateCatalogEntry(
        id: 'CT_TEE_EQ',
        name: 'Cable Tray Equal Tee',
        category: 'Fittings',
        productCode: 'CT-TEE-100x50x100',
        description: '90° 3-way junction tee with identical run and branch dimensions.',
        template: TemplateParameterDefinition.cableTrayTee(width: 100, height: 50, branchWidth: 100),
        defaultDimensions: {'width': 100.0, 'height': 50.0, 'branchWidth': 100.0},
      ),
      _TemplateCatalogEntry(
        id: 'CT_TEE_UNQ',
        name: 'Cable Tray Unequal Tee',
        category: 'Fittings',
        productCode: 'CT-TEE-100x50x150',
        description: '3-way tee fitting with independent branch width expansion.',
        template: TemplateParameterDefinition.cableTrayTee(width: 100, height: 50, branchWidth: 150),
        defaultDimensions: {'width': 100.0, 'height': 50.0, 'branchWidth': 150.0},
      ),
      _TemplateCatalogEntry(
        id: 'CT_REDUCER',
        name: 'Cable Tray Reducer',
        category: 'Fittings',
        productCode: 'CT-RED-150x50x100',
        description: 'Concentric rectangular transition reducer preserving straight wall tapers.',
        template: TemplateParameterDefinition.cableTrayReducer(widthIn: 150, widthOut: 100, height: 50, length: 400),
        defaultDimensions: {'widthIn': 150.0, 'widthOut': 100.0, 'height': 50.0, 'length': 400.0},
      ),
      _TemplateCatalogEntry(
        id: 'CT_BEND_90',
        name: '90° Flat Radius Elbow',
        category: 'Fittings',
        productCode: 'CT-BEND90-100x50',
        description: 'Segmented 90° flat elbow for horizontal cable path redirection.',
        template: TemplateParameterDefinition.cableTrayBend90(width: 100, height: 50, radius: 100),
        defaultDimensions: {'width': 100.0, 'height': 50.0, 'radius': 100.0},
      ),
      _TemplateCatalogEntry(
        id: 'CT_BEND_45',
        name: '45° Flat Radius Elbow',
        category: 'Fittings',
        productCode: 'CT-BEND45-100x50',
        description: '45° smooth radius elbow for oblique duct routing.',
        template: TemplateParameterDefinition.cableTrayBend45(width: 100, height: 50, radius: 100),
        defaultDimensions: {'width': 100.0, 'height': 50.0, 'radius': 100.0},
      ),
      _TemplateCatalogEntry(
        id: 'CT_CROSS',
        name: '4-Way Cross Fitting',
        category: 'Fittings',
        productCode: 'CT-CROSS-100x50',
        description: '4-way equal junction for multi-direction cable distribution.',
        template: TemplateParameterDefinition.cableTrayCross(widthMain: 100, widthBranch: 100, height: 50),
        defaultDimensions: {'width': 100.0, 'height': 50.0},
      ),
      _TemplateCatalogEntry(
        id: 'TR_STRAIGHT',
        name: 'Straight Cable Trunking',
        category: 'Trunking',
        productCode: 'TR-100x50x3000',
        description: 'Enclosed straight trunking body with return flanges.',
        template: TemplateParameterDefinition.cableTrayStraight(width: 100, height: 50, length: 1000),
        defaultDimensions: {'width': 100.0, 'height': 50.0, 'length': 1000.0},
      ),
      _TemplateCatalogEntry(
        id: 'CV_COVER',
        name: 'Snap-On Tray Cover',
        category: 'Covers',
        productCode: 'CV-100x3000',
        description: 'Protective top cover plate with pre-punched grounding tabs.',
        template: TemplateParameterDefinition.cableTrayStraight(width: 100, height: 15, length: 1000),
        defaultDimensions: {'width': 100.0, 'height': 15.0, 'length': 1000.0},
      ),
    ];
  }

  void _selectEntry(_TemplateCatalogEntry entry) {
    setState(() {
      _selectedEntry = entry;
      _liveParameters.clear();
      _liveParameters.addAll(entry.defaultDimensions);
    });
  }

  void _openAuthoringWizard() {
    showDialog<TemplateParameterDefinition>(
      context: context,
      builder: (ctx) => TemplateAuthoringWizardDialog(
        viewModel: widget.viewModel,
        onTemplateCreated: (newDef) {
          final newEntry = _TemplateCatalogEntry(
            id: newDef.templateId,
            name: newDef.name,
            category: newDef.category,
            productCode: newDef.productType,
            description: 'User authored parametric template',
            template: newDef,
            defaultDimensions: Map<String, double>.from(newDef.baselineParameters),
          );
          setState(() {
            _catalog.insert(0, newEntry);
            _selectEntry(newEntry);
          });
        },
      ),
    );
  }

  void _instantiateSelected() {
    if (_selectedEntry == null) return;
    final entry = _selectedEntry!;

    if (widget.onInstantiate != null) {
      widget.onInstantiate!(entry.template, _liveParameters);
    } else if (widget.viewModel != null) {
      widget.viewModel!.loadTemplate(entry.template);
      for (final p in _liveParameters.entries) {
        widget.viewModel!.updateTemplateParameter(p.key, p.value);
      }
    }
    Navigator.of(context).pop(entry.template);
  }

  List<_TemplateCatalogEntry> get _filteredCatalog {
    return _catalog.where((entry) {
      final matchesCat = _selectedCategory == 'All' || entry.category == _selectedCategory;
      final matchesSearch = _searchQuery.isEmpty ||
          entry.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          entry.productCode.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          entry.description.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesCat && matchesSearch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    return Dialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF334155), width: 1.2),
      ),
      child: Container(
        width: (screen.width * 0.95).clamp(700.0, 1060.0),
        height: (screen.height * 0.92).clamp(480.0, 700.0),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const SizedBox(height: 14),
            _buildFilterRow(),
            const Divider(color: Color(0xFF334155), height: 20),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 6,
                    child: _buildCatalogGrid(),
                  ),
                  const VerticalDivider(color: Color(0xFF334155), width: 20),
                  Expanded(
                    flex: 4,
                    child: _buildInspectorPanel(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF0284C7).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.dashboard_customize, color: Color(0xFF38BDF8), size: 22),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Parametric Template & Catalog Library',
                overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Color(0xFFF8FAFC),
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Select standard fittings or author custom parameter-driven sheet metal templates',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.add, size: 14),
          label: const Text('Author Template from DXF...', style: TextStyle(fontSize: 12)),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF38BDF8),
            side: const BorderSide(color: Color(0xFF0284C7)),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          ),
          onPressed: _openAuthoringWizard,
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.close, color: Color(0xFF94A3B8)),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Close Gallery',
        ),
      ],
    );
  }

  Widget _buildFilterRow() {
    final categories = ['All', 'Cable Trays', 'Fittings', 'Covers', 'Trunking'];

    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: categories.map((cat) {
                final isSelected = _selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(cat),
                    selected: isSelected,
                    selectedColor: const Color(0xFF0284C7),
                    backgroundColor: const Color(0xFF0F172A),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                    onSelected: (_) => setState(() => _selectedCategory = cat),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 220,
          height: 34,
          child: TextField(
            style: const TextStyle(color: Color(0xFFF8FAFC), fontSize: 11),
            decoration: InputDecoration(
              hintText: 'Search catalog...',
              hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
              prefixIcon: const Icon(Icons.search, size: 15, color: Color(0xFF64748B)),
              filled: true,
              fillColor: const Color(0xFF0F172A),
              contentPadding: EdgeInsets.zero,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFF334155)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFF334155)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFF38BDF8)),
              ),
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
        ),
      ],
    );
  }

  Widget _buildCatalogGrid() {
    final entries = _filteredCatalog;

    if (entries.isEmpty) {
      return const Center(
        child: Text('No templates matching filter', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
      );
    }

    return GridView.builder(
      itemCount: entries.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.15,
      ),
      itemBuilder: (context, idx) {
        final entry = entries[idx];
        final isSelected = _selectedEntry?.id == entry.id;

        return GestureDetector(
          onTap: () => _selectEntry(entry),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF0284C7).withValues(alpha: 0.15)
                  : const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF334155),
                width: isSelected ? 1.6 : 1.0,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF334155).withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        entry.category,
                        style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        entry.productCode,
                        style: const TextStyle(color: Color(0xFF64748B), fontSize: 9, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  entry.name,
                  style: TextStyle(
                    color: isSelected ? const Color(0xFFF8FAFC) : const Color(0xFFE2E8F0),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Expanded(
                  child: Text(
                    entry.description,
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10, height: 1.2),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  children: entry.defaultDimensions.entries.map((p) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Text(
                        '${p.key}:${p.value.toInt()}mm',
                        style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 8.5),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInspectorPanel() {
    if (_selectedEntry == null) {
      return const Center(child: Text('Select a template to view details', style: TextStyle(color: Color(0xFF94A3B8))));
    }
    final entry = _selectedEntry!;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            entry.name,
            style: const TextStyle(color: Color(0xFFF8FAFC), fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            'Product: ${entry.productCode} | Category: ${entry.category}',
            style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10),
          ),
          const SizedBox(height: 10),

          // Live 2D Vector Preview Container
          Container(
            height: 160,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: CustomPaint(
              painter: _TemplatePreviewPainter(
                templateId: entry.id,
                parameters: _liveParameters,
              ),
            ),
          ),
          const SizedBox(height: 12),

          const Text(
            'Parametric Morphing Dimensions',
            style: TextStyle(color: Color(0xFFF8FAFC), fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),

          ..._liveParameters.entries.map((param) {
            final key = param.key;
            final val = param.value;
            final double minVal = (key.contains('height') ? 25.0 : 50.0);
            final double maxVal = (key.contains('length') ? 3000.0 : 600.0);

            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        key.toUpperCase(),
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${val.toStringAsFixed(0)} mm',
                        style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderThemeData(
                      thumbColor: const Color(0xFF38BDF8),
                      activeTrackColor: const Color(0xFF0284C7),
                      inactiveTrackColor: const Color(0xFF334155),
                      overlayColor: const Color(0xFF0284C7).withValues(alpha: 0.2),
                      trackHeight: 2.5,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                    ),
                    child: Slider(
                      value: val.clamp(minVal, maxVal),
                      min: minVal,
                      max: maxVal,
                      divisions: ((maxVal - minVal) / 10).round().clamp(1, 300),
                      onChanged: (newVal) {
                        setState(() {
                          _liveParameters[key] = newVal;
                        });
                      },
                    ),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 10),

          ElevatedButton.icon(
            icon: const Icon(Icons.open_in_new, size: 14),
            label: const Text('Instantiate in Studio', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            onPressed: _instantiateSelected,
          ),
        ],
      ),
    );
  }
}

class _TemplatePreviewPainter extends CustomPainter {
  final String templateId;
  final Map<String, double> parameters;

  _TemplatePreviewPainter({
    required this.templateId,
    required this.parameters,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final fillPaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = const Color(0xFF38BDF8)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;
    final bendPaint = Paint()
      ..color = const Color(0xFFF59E0B)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final w = parameters['width'] ?? parameters['widthIn'] ?? 100.0;
    final scale = (size.width * 0.7) / 400.0;

    final path = Path();
    if (templateId.contains('TEE') || templateId == 'CT_TEE_EQ' || templateId == 'CT_TEE_UNQ') {
      final bw = parameters['branchWidth'] ?? w;
      final armW = (w * 0.4 * scale).clamp(20.0, 60.0);
      final brW = (bw * 0.4 * scale).clamp(20.0, 60.0);

      path.moveTo(center.dx - 60, center.dy + armW);
      path.lineTo(center.dx + 60, center.dy + armW);
      path.lineTo(center.dx + 60, center.dy - armW);
      path.lineTo(center.dx + brW, center.dy - armW);
      path.lineTo(center.dx + brW, center.dy - armW - 35);
      path.lineTo(center.dx - brW, center.dy - armW - 35);
      path.lineTo(center.dx - brW, center.dy - armW);
      path.lineTo(center.dx - 60, center.dy - armW);
      path.close();

      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, strokePaint);

      canvas.drawLine(Offset(center.dx - 60, center.dy + armW * 0.5), Offset(center.dx + 60, center.dy + armW * 0.5), bendPaint);
      canvas.drawLine(Offset(center.dx - 60, center.dy - armW * 0.5), Offset(center.dx + 60, center.dy - armW * 0.5), bendPaint);
    } else if (templateId.contains('RED') || templateId == 'CT_REDUCER') {
      final wIn = (parameters['widthIn'] ?? 150.0) * 0.25 * scale;
      final wOut = (parameters['widthOut'] ?? 100.0) * 0.25 * scale;

      path.moveTo(center.dx - 50, center.dy - wIn);
      path.lineTo(center.dx + 50, center.dy - wOut);
      path.lineTo(center.dx + 50, center.dy + wOut);
      path.lineTo(center.dx - 50, center.dy + wIn);
      path.close();

      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, strokePaint);
    } else if (templateId.contains('BEND') || templateId == 'CT_BEND_90' || templateId == 'CT_BEND_45') {
      final rect = Rect.fromCircle(center: Offset(center.dx - 25, center.dy + 25), radius: 50);
      canvas.drawArc(rect, -1.57, 1.57, false, strokePaint..strokeWidth = 20);
    } else {
      final halfW = (w * 0.22 * scale).clamp(12.0, 45.0);
      final halfL = 55.0;

      path.addRect(Rect.fromCenter(center: center, width: halfL * 2, height: halfW * 2));
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, strokePaint);

      canvas.drawLine(Offset(center.dx - halfL, center.dy - halfW * 0.6), Offset(center.dx + halfL, center.dy - halfW * 0.6), bendPaint);
      canvas.drawLine(Offset(center.dx - halfL, center.dy + halfW * 0.6), Offset(center.dx + halfL, center.dy + halfW * 0.6), bendPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TemplatePreviewPainter oldDelegate) => true;
}
