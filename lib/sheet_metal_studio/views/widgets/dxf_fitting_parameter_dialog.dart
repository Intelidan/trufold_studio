// =============================================================================
// dxf_fitting_parameter_dialog.dart
//
// DSF Fitting Inspector & Auto Fold Dialog.
// Light CAD Theme (Crisp white & slate backgrounds with clean engineering styling).
// Dynamic Category, Product, and Variant population directly from product_variations.csv.
// Multi-Port Cards with Interactive [Select W Edge 📏] and [Select H Edge(s) 📐] picking.
// Header W×H Tags visibility toggle, analyzed geometry banner, flange presets,
// parameter attachment to DSF drawings, and 1-Click "Auto Fold".
// =============================================================================

import 'package:flutter/material.dart';
import '../../engine/fitting_port_annotation_engine.dart';
import '../../models/dxf_fitting_metadata.dart';
import '../../services/product_catalog_service.dart';
import '../../viewmodels/sheet_metal_studio_viewmodel.dart';

class DxfFittingParameterDialog extends StatefulWidget {
  final SheetMetalStudioViewModel viewModel;
  final VoidCallback? onAutoFoldCompleted;
  final VoidCallback? onClose;
  final void Function(DragStartDetails)? onDragStartHeader;
  final void Function(DragUpdateDetails)? onDragHeader;

  const DxfFittingParameterDialog({
    super.key,
    required this.viewModel,
    this.onAutoFoldCompleted,
    this.onClose,
    this.onDragStartHeader,
    this.onDragHeader,
  });

  static Future<void> show(
    BuildContext context, {
    required SheetMetalStudioViewModel viewModel,
    VoidCallback? onAutoFoldCompleted,
  }) {
    viewModel.setFittingInspectorOpen(true);
    final isStudioInTree = context.findAncestorStateOfType<State>()?.widget.runtimeType.toString().contains('SheetMetalStudioScreen') ?? false;
    if (!isStudioInTree) {
      return showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => DxfFittingParameterDialog(
          viewModel: viewModel,
          onAutoFoldCompleted: onAutoFoldCompleted,
        ),
      );
    }
    return Future.value();
  }

  @override
  State<DxfFittingParameterDialog> createState() => _DxfFittingParameterDialogState();
}

class _DxfFittingParameterDialogState extends State<DxfFittingParameterDialog> {
  late String _selectedCategory;
  late String _selectedProduct;
  late String _selectedVariantName;
  late double _flangeMm;

  // Controllers for parameters
  final Map<String, TextEditingController> _controllers = {};
  late TextEditingController _thicknessController;
  late Map<String, double> _currentParams;
  late Map<String, double> _analyzed;
  late Map<String, String> _portAssignments;

  @override
  void initState() {
    super.initState();
    final meta = widget.viewModel.detectedFittingMetadata ??
        DxfFittingMetadata.detectFromDocument(widget.viewModel.document);

    _selectedCategory = meta.category;
    _selectedProduct = meta.product;
    _selectedVariantName = meta.variantName;
    _flangeMm = meta.flangeMm;
    _currentParams = Map<String, double>.from(meta.parameters);
    _analyzed = Map<String, double>.from(meta.analyzedDimensions);
    _portAssignments = meta.portAssignments != null
        ? Map<String, String>.from(meta.portAssignments!)
        : _detectInitialPortAssignments(meta);

    final currentThk = widget.viewModel.document.material.thicknessMm;
    _thicknessController = TextEditingController(
      text: (_currentParams['thickness'] ?? currentThk).toStringAsFixed(1),
    );

    _syncControllers();
  }

  Map<String, String> _detectInitialPortAssignments(DxfFittingMetadata meta) {
    final openings = meta.getPortOpenings(widget.viewModel.document);
    final map = <String, String>{};
    for (final op in openings) {
      map[op.id] = op.side.name;
    }
    return map;
  }

  void _syncControllers() {
    for (final entry in _currentParams.entries) {
      if (!_controllers.containsKey(entry.key)) {
        _controllers[entry.key] = TextEditingController(text: entry.value.toStringAsFixed(0));
      } else {
        _controllers[entry.key]!.text = entry.value.toStringAsFixed(0);
      }
    }
  }

  @override
  void dispose() {
    _thicknessController.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _onCategoryChanged(String? newCat) {
    if (newCat == null || newCat == _selectedCategory) return;
    setState(() {
      _selectedCategory = newCat;
      if (newCat == 'None') {
        _selectedProduct = 'None';
        _selectedVariantName = 'None';
        _applyAnalyzedDefaults();
      } else {
        final availableProducts = FittingCatalogRegistry.getProductsForCategory(_selectedCategory);
        if (!availableProducts.contains(_selectedProduct)) {
          _selectedProduct = availableProducts.isNotEmpty ? availableProducts.first : 'None';
        }
        _updateVariantOptions();
      }
    });
  }

  void _onProductChanged(String? newProd) {
    if (newProd == null || newProd == _selectedProduct) return;
    setState(() {
      _selectedProduct = newProd;
      if (newProd == 'None') {
        _selectedVariantName = 'None';
        _applyAnalyzedDefaults();
      } else {
        _updateVariantOptions();
      }
    });
  }

  void _updateVariantOptions() {
    final variants = FittingCatalogRegistry.getVariantsForProduct(_selectedCategory, _selectedProduct);
    if (variants.isNotEmpty) {
      _selectedVariantName = variants.first.name;
      _applyVariant(variants.first);
    } else {
      _selectedVariantName = 'None';
      _applyAnalyzedDefaults();
    }
  }

  void _onVariantChanged(String? newVar) {
    if (newVar == null || newVar == _selectedVariantName) return;
    setState(() {
      _selectedVariantName = newVar;
      if (newVar == 'None' || newVar == 'Custom') {
        _applyAnalyzedDefaults();
      } else {
        final variants = FittingCatalogRegistry.getVariantsForProduct(_selectedCategory, _selectedProduct);
        final match = variants.where((v) => v.name == newVar).firstOrNull;
        if (match != null) {
          _applyVariant(match);
        }
      }
    });
  }

  void _applyVariant(FittingVariant v) {
    _flangeMm = v.flangeMm;
    _currentParams.addAll(v.parameters);
    _syncControllers();
  }

  void _applyAnalyzedDefaults() {
    final tempMeta = DxfFittingMetadata.detectFromDocument(widget.viewModel.document);
    _flangeMm = tempMeta.flangeMm;
    _currentParams = Map<String, double>.from(tempMeta.parameters);
    _syncControllers();
  }

  DxfFittingMetadata _buildCurrentMetadata() {
    final parsedParams = <String, double>{};
    for (final entry in _controllers.entries) {
      parsedParams[entry.key] = double.tryParse(entry.value.text) ?? (_currentParams[entry.key] ?? 50.0);
    }
    final thk = double.tryParse(_thicknessController.text);
    if (thk != null && thk > 0) {
      parsedParams['thickness'] = thk;
    }

    final currentMeta = widget.viewModel.detectedFittingMetadata;

    return DxfFittingMetadata(
      category: _selectedCategory,
      product: _selectedProduct,
      variantName: _selectedVariantName,
      flangeMm: _flangeMm,
      parameters: parsedParams,
      analyzedDimensions: _analyzed,
      portAssignments: _portAssignments,
      manualPortEdges: currentMeta?.manualPortEdges,
      portBadgeOffsets: currentMeta?.portBadgeOffsets,
    );
  }

  void _handleSaveParametersOnly() {
    final meta = _buildCurrentMetadata();
    final thk = double.tryParse(_thicknessController.text);
    if (thk != null && thk > 0) {
      widget.viewModel.setSheetThickness(thk);
    }
    widget.viewModel.updateFittingMetadata(meta);

    if (widget.onClose != null) {
      widget.onClose!();
    } else if (Navigator.canPop(context)) {
      Navigator.of(context).pop();
    }
    widget.viewModel.setFittingInspectorOpen(false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Fitting parameters attached to DSF drawing: ${meta.product} (${meta.variantName}) | THK: ${widget.viewModel.document.material.thicknessMm.toStringAsFixed(1)}mm'),
        backgroundColor: const Color(0xFF0F766E),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _startEdgePick(PortEdgePickTarget target) {
    final meta = _buildCurrentMetadata();
    final thk = double.tryParse(_thicknessController.text);
    if (thk != null && thk > 0) {
      widget.viewModel.setSheetThickness(thk);
    }
    widget.viewModel.updateFittingMetadata(meta);

    if (widget.onClose != null) {
      widget.onClose!();
    } else if (Navigator.canPop(context)) {
      Navigator.of(context).pop();
    }
    widget.viewModel.setFittingInspectorOpen(false);
    widget.viewModel.startPortEdgePick(target);
  }

  void _clearManualEdge(String portId, bool isWidth) {
    final meta = _buildCurrentMetadata();
    final manual = Map<String, Map<String, dynamic>>.from(meta.manualPortEdges ?? {});
    if (manual.containsKey(portId)) {
      final entry = Map<String, dynamic>.from(manual[portId]!);
      if (isWidth) {
        entry.remove('widthEdge');
      } else {
        entry.remove('heightEdges');
      }
      if (entry.isEmpty) {
        manual.remove(portId);
      } else {
        manual[portId] = entry;
      }
    }
    final updated = meta.copyWith(manualPortEdges: manual);
    widget.viewModel.updateFittingMetadata(updated);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final availableCategories = FittingCategory.all;
    final availableProducts = [
      'None',
      ...FittingCatalogRegistry.getProductsForCategory(_selectedCategory),
    ];
    final availableVariants = FittingCatalogRegistry.getVariantsForProduct(_selectedCategory, _selectedProduct);
    final variantNames = ['None', ...availableVariants.map((v) => v.name)];
    if (!variantNames.contains(_selectedVariantName)) {
      variantNames.add(_selectedVariantName);
    }

    final portCount = ProductCatalogService.getPortCount(_selectedProduct, _selectedVariantName);

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
      ),
      child: Container(
        width: 700,
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 580),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Header (Light Engineering CAD Theme - Draggable)
            MouseRegion(
              cursor: widget.onDragHeader != null ? SystemMouseCursors.move : SystemMouseCursors.basic,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: widget.onDragStartHeader,
                onPanUpdate: widget.onDragHeader,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.straighten, color: Color(0xFF0284C7), size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'DSF Fitting Inspector',
                                style: TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (widget.onDragHeader != null) ...[
                                const SizedBox(width: 6),
                                const Icon(Icons.drag_indicator, size: 14, color: Color(0xFF94A3B8)),
                              ],
                            ],
                          ),
                          const SizedBox(height: 1),
                          const Text(
                            'Classify fitting and review Width (W) & Height (H) port dimensions.',
                            style: TextStyle(color: Color(0xFF64748B), fontSize: 10.5),
                          ),
                        ],
                      ),
                    ),
                    // W×H Tags Visibility Toggle
                    OutlinedButton.icon(
                      onPressed: () {
                        widget.viewModel.togglePortOpeningBadges();
                        setState(() {});
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: widget.viewModel.showPortOpeningBadges
                            ? const Color(0xFF0D9488)
                            : const Color(0xFF64748B),
                        side: BorderSide(
                          color: widget.viewModel.showPortOpeningBadges
                              ? const Color(0xFF0D9488)
                              : const Color(0xFFCBD5E1),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      icon: Icon(
                        widget.viewModel.showPortOpeningBadges ? Icons.label : Icons.label_off_outlined,
                        size: 13,
                      ),
                      label: Text(
                        widget.viewModel.showPortOpeningBadges ? 'W×H Tags: ON' : 'W×H Tags: OFF',
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.close, color: Color(0xFF64748B), size: 18),
                      onPressed: () {
                        if (widget.onClose != null) {
                          widget.onClose!();
                        } else if (Navigator.canPop(context)) {
                          Navigator.of(context).pop();
                        }
                        widget.viewModel.setFittingInspectorOpen(false);
                      },
                      tooltip: 'Close',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Divider(color: Color(0xFFE2E8F0), height: 1),
            const SizedBox(height: 10),

            // 2. Scrollable Body
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // A. Searchable Dropdowns & Sheet Metal Thickness
                    _buildSectionHeader('1. CATALOG CLASSIFICATION & THICKNESS', Icons.category_outlined),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        // Dropdown 1: Category
                        Expanded(
                          flex: 3,
                          child: _buildSearchableDropdown(
                            label: 'Category',
                            value: _selectedCategory,
                            items: availableCategories,
                            onChanged: _onCategoryChanged,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Dropdown 2: Product
                        Expanded(
                          flex: 3,
                          child: _buildSearchableDropdown(
                            label: 'Product',
                            value: _selectedProduct,
                            items: availableProducts,
                            onChanged: _onProductChanged,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Dropdown 3: Variant
                        Expanded(
                          flex: 4,
                          child: _buildSearchableDropdown(
                            label: 'Variant',
                            value: _selectedVariantName,
                            items: variantNames,
                            onChanged: _onVariantChanged,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Entry 4: Thickness (mm)
                        Expanded(
                          flex: 2,
                          child: _buildThicknessInput(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // B. Analyzed Geometry Banner
                    _buildAnalyzedInfoBanner(),
                    const SizedBox(height: 12),

                    // C. Parameters Entry Section
                    _buildSectionHeader(
                      '2. PORT PARAMETERS ($portCount OPENING${portCount > 1 ? 'S' : ''}) & EDGE ASSIGNMENT',
                      Icons.straighten,
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'Right-click any edge on canvas to assign directly, or use buttons below.',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 10),
                    ),
                    const SizedBox(height: 8),

                    _buildPortCardsSection(portCount),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),
            const Divider(color: Color(0xFFE2E8F0), height: 1),
            const SizedBox(height: 10),

            // 3. Bottom Action Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    if (widget.onClose != null) {
                      widget.onClose!();
                    } else if (Navigator.canPop(context)) {
                      Navigator.of(context).pop();
                    }
                    widget.viewModel.setFittingInspectorOpen(false);
                  },
                  child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: _handleSaveParametersOnly,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    elevation: 1,
                  ),
                  icon: const Icon(Icons.check, size: 15),
                  label: const Text(
                    'Save Parameters to DSF',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThicknessInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.line_weight, size: 12, color: Color(0xFF0284C7)),
            const SizedBox(width: 3),
            const Expanded(
              child: Text(
                'Thk (mm)',
                style: TextStyle(
                  color: Color(0xFF475569),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            PopupMenuButton<double>(
              tooltip: 'Standard thickness presets',
              icon: const Icon(Icons.arrow_drop_down, size: 14, color: Color(0xFF64748B)),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onSelected: (val) {
                setState(() {
                  _thicknessController.text = val.toStringAsFixed(1);
                });
              },
              itemBuilder: (ctx) => [
                0.8, 1.0, 1.2, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0,
              ].map((t) => PopupMenuItem(
                value: t,
                height: 28,
                child: Text('${t.toStringAsFixed(1)} mm', style: const TextStyle(fontSize: 11)),
              )).toList(),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Container(
          height: 34,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          child: TextField(
            controller: _thicknessController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: InputBorder.none,
              suffixText: 'mm',
              suffixStyle: TextStyle(fontSize: 10, color: Color(0xFF64748B)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 15, color: const Color(0xFF0284C7)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF334155),
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchableDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    final effectiveValue = items.contains(value) ? value : (items.isNotEmpty ? items.first : 'None');
    final isNone = effectiveValue == 'None';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF475569), fontSize: 11, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(width: 4),
            const Text('Searchable', style: TextStyle(color: Color(0xFF0284C7), fontSize: 9.5)),
          ],
        ),
        const SizedBox(height: 4),
        InkWell(
          key: Key('searchable_dropdown_$label'),
          onTap: () async {
            final selected = await _showSearchableSelectionDialog(
              context: context,
              title: 'Select $label',
              currentValue: effectiveValue,
              items: items,
            );
            if (selected != null) {
              onChanged(selected);
            }
          },
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isNone ? const Color(0xFFCBD5E1) : const Color(0xFF0284C7),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    effectiveValue,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isNone ? const Color(0xFF94A3B8) : const Color(0xFF0F172A),
                      fontSize: 12,
                      fontWeight: isNone ? FontWeight.normal : FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.search, color: Color(0xFF0284C7), size: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<String?> _showSearchableSelectionDialog({
    required BuildContext context,
    required String title,
    required String currentValue,
    required List<String> items,
  }) {
    final distinctItems = <String>[];
    if (!items.contains('None')) {
      distinctItems.add('None');
    }
    for (final it in items) {
      if (!distinctItems.contains(it)) {
        distinctItems.add(it);
      }
    }

    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final filteredItems = distinctItems.where((item) {
              if (searchQuery.isEmpty) return true;
              return item.toLowerCase().contains(searchQuery.toLowerCase());
            }).toList();

            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
              ),
              child: Container(
                width: 420,
                constraints: const BoxConstraints(maxHeight: 520),
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Row(
                      children: [
                        const Icon(Icons.manage_search, color: Color(0xFF0284C7), size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Color(0xFF64748B), size: 18),
                          onPressed: () => Navigator.of(dialogCtx).pop(),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Search Input
                    Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.5)),
                      ),
                      child: TextField(
                        autofocus: true,
                        style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Search options or select None...',
                          hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                          prefixIcon: const Icon(Icons.search, color: Color(0xFF0284C7), size: 18),
                          suffixIcon: searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, color: Color(0xFF64748B), size: 16),
                                  onPressed: () {
                                    setDialogState(() => searchQuery = '');
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        onChanged: (val) {
                          setDialogState(() => searchQuery = val);
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Divider(color: Color(0xFFE2E8F0), height: 1),
                    const SizedBox(height: 8),
                    // Filtered List
                    Flexible(
                      child: filteredItems.isEmpty
                          ? Container(
                              padding: const EdgeInsets.all(24),
                              alignment: Alignment.center,
                              child: const Text(
                                'No matching options found.\nYou can select "None" or clear your search query.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: filteredItems.length,
                              itemBuilder: (ctx, idx) {
                                final item = filteredItems[idx];
                                final isSelected = item == currentValue;
                                final isNone = item == 'None';

                                return InkWell(
                                  onTap: () => Navigator.of(dialogCtx).pop(item),
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    margin: const EdgeInsets.only(bottom: 4),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? const Color(0xFFCCFBF1)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: isSelected
                                            ? const Color(0xFF0D9488)
                                            : Colors.transparent,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isNone
                                              ? Icons.block
                                              : (isSelected
                                                  ? Icons.check_circle
                                                  : Icons.radio_button_unchecked),
                                          size: 16,
                                          color: isNone
                                              ? Colors.amber.shade700
                                              : (isSelected
                                                  ? const Color(0xFF0D9488)
                                                  : const Color(0xFF94A3B8)),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            item,
                                            style: TextStyle(
                                              color: isNone
                                                  ? Colors.amber.shade800
                                                  : const Color(0xFF0F172A),
                                              fontSize: 12.5,
                                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                            ),
                                          ),
                                        ),
                                        if (isSelected)
                                          const Text(
                                            'Active',
                                            style: TextStyle(
                                              color: Color(0xFF0D9488),
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAnalyzedInfoBanner() {
    final width = _analyzed['overallWidth']?.toStringAsFixed(1) ?? '--';
    final height = _analyzed['overallHeight']?.toStringAsFixed(1) ?? '--';
    final flange = _analyzed['detectedFlangeMm']?.toStringAsFixed(1) ?? '--';
    final branch = _analyzed['branchWidth']?.toStringAsFixed(0) ?? '--';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFBAE6FD)),
      ),
      child: Row(
        children: [
          const Icon(Icons.analytics_outlined, color: Color(0xFF0284C7), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Drawing Geometry Analysis: $width mm × $height mm  |  Tab Flange: $flange mm  |  Branch: $branch mm',
                  style: const TextStyle(color: Color(0xFF0369A1), fontSize: 11, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  _selectedVariantName == 'None'
                      ? 'Catalog mode: None (orienting directly from drawing boundary dots).'
                      : 'Catalog mode: $_selectedProduct ($_selectedVariantName). Parameters shown with manual drawing picks.',
                  style: const TextStyle(color: Color(0xFF0284C7), fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPortCardsSection(int portCount) {
    if (portCount == 4) {
      return _buildFourPortCards();
    } else if (portCount == 3) {
      return _buildThreePortCards();
    } else if (portCount == 2) {
      return _buildTwoPortCards();
    } else if (portCount == 1) {
      return _buildSinglePortCard();
    } else {
      return _buildStandardParametersGrid();
    }
  }

  Widget _buildTwoPortCards() {
    final isReducer = _selectedProduct.toLowerCase().contains('reducer');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _buildPortCard(
            title: isReducer ? 'Entry Port (Inlet)' : 'Port 1 (Inlet / Opening 1)',
            portId: 'port1',
            widthKey: isReducer ? 'widthIn' : 'port1Width',
            heightKey: 'port1Height',
            accentColor: const Color(0xFF0284C7),
            defaultSide: 'west',
            pickTargetWidth: PortEdgePickTarget.port1Width,
            pickTargetHeight: PortEdgePickTarget.port1Height,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildPortCard(
            title: isReducer ? 'Exit Port (Outlet)' : 'Port 2 (Outlet / Opening 2)',
            portId: 'port2',
            widthKey: isReducer ? 'widthOut' : 'port2Width',
            heightKey: 'port2Height',
            accentColor: const Color(0xFF0D9488),
            defaultSide: 'east',
            pickTargetWidth: PortEdgePickTarget.port2Width,
            pickTargetHeight: PortEdgePickTarget.port2Height,
          ),
        ),
      ],
    );
  }

  Widget _buildThreePortCards() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Port 1
        Expanded(
          child: _buildPortCard(
            title: 'Port 1 (Main In)',
            portId: 'port1',
            widthKey: 'port1Width',
            heightKey: 'port1Height',
            accentColor: const Color(0xFF0284C7),
            defaultSide: 'west',
            pickTargetWidth: PortEdgePickTarget.port1Width,
            pickTargetHeight: PortEdgePickTarget.port1Height,
          ),
        ),
        const SizedBox(width: 10),
        // Port 2
        Expanded(
          child: _buildPortCard(
            title: 'Port 2 (Main Out)',
            portId: 'port2',
            widthKey: 'port2Width',
            heightKey: 'port2Height',
            accentColor: const Color(0xFF0D9488),
            defaultSide: 'east',
            pickTargetWidth: PortEdgePickTarget.port2Width,
            pickTargetHeight: PortEdgePickTarget.port2Height,
          ),
        ),
        const SizedBox(width: 10),
        // Port 3
        Expanded(
          child: _buildPortCard(
            title: 'Port 3 (Tee Branch)',
            portId: 'port3',
            widthKey: 'port3Width',
            heightKey: 'port3Height',
            accentColor: const Color(0xFF7C3AED),
            defaultSide: 'north',
            pickTargetWidth: PortEdgePickTarget.port3Width,
            pickTargetHeight: PortEdgePickTarget.port3Height,
          ),
        ),
      ],
    );
  }

  Widget _buildFourPortCards() {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildPortCard(
                title: 'Port 1 (West In)',
                portId: 'port1',
                widthKey: 'port1Width',
                heightKey: 'port1Height',
                accentColor: const Color(0xFF0284C7),
                defaultSide: 'west',
                pickTargetWidth: PortEdgePickTarget.port1Width,
                pickTargetHeight: PortEdgePickTarget.port1Height,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildPortCard(
                title: 'Port 2 (East Out)',
                portId: 'port2',
                widthKey: 'port2Width',
                heightKey: 'port2Height',
                accentColor: const Color(0xFF0D9488),
                defaultSide: 'east',
                pickTargetWidth: PortEdgePickTarget.port2Width,
                pickTargetHeight: PortEdgePickTarget.port2Height,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildPortCard(
                title: 'Port 3 (North Branch)',
                portId: 'port3',
                widthKey: 'port3Width',
                heightKey: 'port3Height',
                accentColor: const Color(0xFF7C3AED),
                defaultSide: 'north',
                pickTargetWidth: PortEdgePickTarget.port3Width,
                pickTargetHeight: PortEdgePickTarget.port3Height,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildPortCard(
                title: 'Port 4 (South Branch)',
                portId: 'port4',
                widthKey: 'port4Width',
                heightKey: 'port4Height',
                accentColor: const Color(0xFFF59E0B),
                defaultSide: 'south',
                pickTargetWidth: PortEdgePickTarget.port4Width,
                pickTargetHeight: PortEdgePickTarget.port4Height,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSinglePortCard() {
    return _buildPortCard(
      title: 'Port 1 (Opening)',
      portId: 'port1',
      widthKey: 'port1Width',
      heightKey: 'port1Height',
      accentColor: const Color(0xFF0284C7),
      defaultSide: 'west',
      pickTargetWidth: PortEdgePickTarget.port1Width,
      pickTargetHeight: PortEdgePickTarget.port1Height,
    );
  }

  Widget _buildPortCard({
    required String title,
    required String portId,
    required String widthKey,
    required String heightKey,
    required Color accentColor,
    required PortEdgePickTarget pickTargetWidth,
    required PortEdgePickTarget pickTargetHeight,
    String? defaultSide,
  }) {
    final meta = widget.viewModel.detectedFittingMetadata;
    final manual = meta?.manualPortEdges?[portId];
    final manualWidth = manual?['widthEdge'] as Map?;
    final manualWidthLen = (manualWidth?['length'] as num?)?.toDouble();

    final manualHeightList = manual?['heightEdges'] as List?;
    final manualHeightLen = manualHeightList != null && manualHeightList.isNotEmpty
        ? ((manualHeightList.last as Map)['length'] as num?)?.toDouble()
        : null;

    final analyzedW = _analyzed[widthKey]?.toStringAsFixed(0) ??
        (_analyzed['detectedPortWidthMm']?.toStringAsFixed(0) ??
            (widthKey == 'port3Width' || widthKey == 'branchWidth'
                ? (_analyzed['branchWidth']?.toStringAsFixed(0) ?? '--')
                : (_analyzed['bedWidth']?.toStringAsFixed(0) ?? '--')));
    final analyzedH = _analyzed[heightKey]?.toStringAsFixed(0) ?? '50';

    final assignedSideName = _portAssignments[portId] ?? defaultSide ?? 'west';
    final currentSide = PortSide.fromString(assignedSideName);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accentColor.withValues(alpha: 0.35), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: accentColor, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<PortSide>(
                tooltip: 'Assign opening side on drawing',
                onSelected: (newSide) {
                  setState(() {
                    _portAssignments[portId] = newSide.name;
                  });
                },
                itemBuilder: (context) => [
                  PortSide.west,
                  PortSide.east,
                  PortSide.north,
                  PortSide.south,
                ].map((s) => PopupMenuItem(
                  value: s,
                  child: Row(
                    children: [
                      Icon(
                        s == currentSide ? Icons.check_circle : Icons.radio_button_unchecked,
                        size: 14,
                        color: s == currentSide ? const Color(0xFF0D9488) : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Text(s.displayName, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                )).toList(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: accentColor.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        currentSide.displayName,
                        style: TextStyle(color: accentColor, fontSize: 9.5, fontWeight: FontWeight.bold),
                      ),
                      Icon(Icons.arrow_drop_down, size: 12, color: accentColor),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Width row + Select W Edge button
          _buildInteractiveParamRow(
            label: 'Width (W)',
            key: widthKey,
            analyzedValue: analyzedW,
            pickTarget: pickTargetWidth,
            pickButtonLabel: 'Select W Edge 📏',
            manualLenMm: manualWidthLen,
            onClearManual: () => _clearManualEdge(portId, true),
          ),
          const SizedBox(height: 10),
          // Height row + Select H Edge button
          _buildInteractiveParamRow(
            label: 'Height (H)',
            key: heightKey,
            analyzedValue: analyzedH,
            pickTarget: pickTargetHeight,
            pickButtonLabel: 'Select H Edge(s) 📐',
            manualLenMm: manualHeightLen,
            onClearManual: () => _clearManualEdge(portId, false),
          ),
        ],
      ),
    );
  }

  Widget _buildInteractiveParamRow({
    required String label,
    required String key,
    required String analyzedValue,
    required PortEdgePickTarget pickTarget,
    required String pickButtonLabel,
    double? manualLenMm,
    VoidCallback? onClearManual,
  }) {
    final controller = _controllers[key] ??= TextEditingController(text: '100');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                label,
                style: const TextStyle(color: Color(0xFF334155), fontSize: 11, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 3,
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Color(0xFF0F172A), fontSize: 12, fontWeight: FontWeight.bold),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 6),
                        ),
                      ),
                    ),
                    const Text('mm', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Pick edge button
            InkWell(
              onTap: () => _startEdgePick(pickTarget),
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.4)),
                ),
                child: Text(
                  pickButtonLabel,
                  style: const TextStyle(color: Color(0xFF0284C7), fontSize: 9.5, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 6),
            if (manualLenMm != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D9488).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF0D9488)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '🎯 Picked: ${manualLenMm.toStringAsFixed(1)} mm',
                      style: const TextStyle(color: Color(0xFF0F766E), fontSize: 9.5, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 3),
                    InkWell(
                      onTap: onClearManual,
                      child: const Icon(Icons.close, size: 11, color: Color(0xFF0F766E)),
                    ),
                  ],
                ),
              ),
            ] else if (analyzedValue != '--') ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.straighten, size: 10, color: Color(0xFF64748B)),
                  const SizedBox(width: 2),
                  Text(
                    'Auto: $analyzedValue mm',
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 9.5),
                  ),
                ],
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildStandardParametersGrid() {
    final keys = _controllers.keys.toList();
    if (keys.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Text(
          'Standard fitting width & height will be automatically derived from boundary dots upon folding.',
          style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
        ),
      );
    }

    return Wrap(
      spacing: 12,
      runSpacing: 10,
      children: keys.map((key) {
        final label = _formatParamLabel(key);
        String? analyzed;
        if (key == 'width' || key == 'bedWidth' || key == 'widthIn') {
          analyzed = _analyzed['bedWidth']?.toStringAsFixed(0) ?? _analyzed['overallWidth']?.toStringAsFixed(0);
        } else if (key == 'branchWidth' || key == 'widthOut') {
          analyzed = _analyzed['branchWidth']?.toStringAsFixed(0);
        } else if (key == 'height') {
          analyzed = '50';
        }

        return SizedBox(
          width: 300,
          child: _buildStandardParamRow(label, key, analyzedValue: analyzed),
        );
      }).toList(),
    );
  }

  String _formatParamLabel(String key) {
    if (key == 'width') return 'Width (W)';
    if (key == 'height') return 'Height (H)';
    if (key == 'branchWidth') return 'Branch Width';
    if (key == 'widthIn') return 'Inlet Width (W1)';
    if (key == 'widthOut') return 'Outlet Width (W2)';
    if (key == 'angle') return 'Bend Angle (°)';
    return key;
  }

  Widget _buildStandardParamRow(String label, String key, {String? analyzedValue}) {
    final controller = _controllers[key] ??= TextEditingController(text: '100');
    final analyzedDisplay = analyzedValue ?? _analyzed[key]?.toStringAsFixed(0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(label, style: const TextStyle(color: Color(0xFF334155), fontSize: 11)),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Color(0xFF0F172A), fontSize: 12, fontWeight: FontWeight.bold),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 6),
                        ),
                      ),
                    ),
                    const Text('mm', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (analyzedDisplay != null && analyzedDisplay != '--') ...[
          const SizedBox(height: 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Icon(Icons.straighten, size: 10, color: Color(0xFF0284C7)),
              const SizedBox(width: 3),
              Text(
                'Analyzed: $analyzedDisplay mm',
                style: const TextStyle(
                  color: Color(0xFF0284C7),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
