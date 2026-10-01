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
import '../../models/cms/cms_product_contract.dart';
import '../../models/cms/cms_physical_port.dart';
import '../../models/dxf_fitting_metadata.dart';
import '../../models/fold_bend_line.dart';
import '../../services/product_catalog_service.dart';
import 'cms_channel_topology_pictograph.dart';
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
  bool _isDeclaredCms = false;

  // Controllers for parameters
  final Map<String, TextEditingController> _controllers = {};
  late TextEditingController _thicknessController;
  late TextEditingController _itemNameController;
  late Map<String, double> _currentParams;
  late Map<String, double> _analyzed;
  late Map<String, String> _portAssignments;
  bool _isLinkedPorts = true;

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

    _isDeclaredCms = widget.viewModel.isCmsDrawing ||
        widget.viewModel.hasVerifiedCmsTemplate ||
        widget.viewModel.document.isCmsDrawing ||
        (_selectedProduct.isNotEmpty && _selectedProduct != 'None');

    final verifiedPorts = widget.viewModel.verifiedCmsPorts;
    if (verifiedPorts.length >= 3) {
      final firstW = verifiedPorts.first.width;
      final firstH = verifiedPorts.first.height;
      for (final p in verifiedPorts) {
        if ((p.width - firstW).abs() > 3.0 || (p.height - firstH).abs() > 3.0) {
          _isLinkedPorts = false;
          break;
        }
      }
    }

    final currentThk = widget.viewModel.document.material.thicknessMm;
    _thicknessController = TextEditingController(
      text: (_currentParams['thickness'] ?? currentThk).toStringAsFixed(1),
    );
    _itemNameController = TextEditingController(
      text: widget.viewModel.document.itemName,
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
    _itemNameController.dispose();
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
        _isDeclaredCms = false;
        _applyAnalyzedDefaults();
      } else {
        _isDeclaredCms = true;
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

    final updatedName = _itemNameController.text.trim();

    final updatedMetadata = Map<String, dynamic>.from(widget.viewModel.document.metadata);
    updatedMetadata['fittingMetadata'] = meta.toJson();
    updatedMetadata['category'] = meta.category;
    updatedMetadata['fittingCategory'] = meta.category;
    updatedMetadata['product'] = meta.product;
    updatedMetadata['fittingProduct'] = meta.product;
    updatedMetadata['variantName'] = meta.variantName;
    updatedMetadata['fittingVariant'] = meta.variantName;

    if (_isDeclaredCms) {
      final contract = CmsProductContract.lookup(_selectedProduct, _selectedVariantName) ??
          CmsProductContract.lookup(meta.product, meta.variantName) ??
          CmsProductContract.lookup(null, updatedName.isNotEmpty ? updatedName : widget.viewModel.document.itemName) ??
          CmsProductContract.lookup(null, widget.viewModel.document.productType) ??
          CmsProductContract.bend45;

      updatedMetadata['isCmsProduct'] = true;
      updatedMetadata['cmsWorkflow'] = {'stage': 'manufacturing_definition', 'stageIndex': 1};
      updatedMetadata['cms_product_contract'] = {
        'productType': contract.productType,
        'variationName': contract.variationName,
        'displayName': contract.displayName,
      };
      if (updatedMetadata['cmsTemplate'] is Map) {
        final cms = Map<String, dynamic>.from(updatedMetadata['cmsTemplate'] as Map);
        cms['category'] = meta.category;
        cms['productType'] = contract.productType;
        cms['variation'] = contract.variationName;
        updatedMetadata['cmsTemplate'] = cms;
      }
      widget.viewModel.updateDocument(
        widget.viewModel.document.copyWith(
          itemName: updatedName.isNotEmpty ? updatedName : widget.viewModel.document.itemName,
          productType: contract.productType,
          metadata: updatedMetadata,
        ),
      );
    } else {
      if (updatedMetadata['cmsTemplate'] is Map) {
        final cms = Map<String, dynamic>.from(updatedMetadata['cmsTemplate'] as Map);
        cms['category'] = meta.category;
        cms['productType'] = meta.product;
        cms['variation'] = meta.variantName;
        updatedMetadata['cmsTemplate'] = cms;
      }
      widget.viewModel.updateDocument(
        widget.viewModel.document.copyWith(
          itemName: updatedName.isNotEmpty ? updatedName : widget.viewModel.document.itemName,
          productType: _selectedProduct != 'None' ? _selectedProduct : widget.viewModel.document.productType,
          metadata: updatedMetadata,
        ),
      );
    }

    widget.viewModel.saveActiveFileDirectIfPossible();

    if (widget.onClose != null) {
      widget.onClose!();
    } else if (Navigator.canPop(context)) {
      Navigator.of(context).pop();
    }
    widget.viewModel.setFittingInspectorOpen(false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✓ Saved category: ${meta.category} | ${meta.product} (${meta.variantName}) to DSF | THK: ${widget.viewModel.document.material.thicknessMm.toStringAsFixed(1)}mm'),
        backgroundColor: const Color(0xFF0F766E),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _handleDeclareAsCmsProduct() {
    final meta = _buildCurrentMetadata();
    final thk = double.tryParse(_thicknessController.text);
    if (thk != null && thk > 0) {
      widget.viewModel.setSheetThickness(thk);
    }
    widget.viewModel.updateFittingMetadata(meta);

    final updatedName = _itemNameController.text.trim();

    // Resolve matching CMS Product Contract
    final contract = CmsProductContract.lookup(_selectedProduct, _selectedVariantName) ??
        CmsProductContract.lookup(meta.product, meta.variantName) ??
        CmsProductContract.lookup(null, updatedName.isNotEmpty ? updatedName : widget.viewModel.document.itemName) ??
        CmsProductContract.lookup(null, widget.viewModel.document.productType) ??
        CmsProductContract.bend45;

    // Attach CMS product flags and category to DSF document
    final updatedMetadata = Map<String, dynamic>.from(widget.viewModel.document.metadata);
    updatedMetadata['fittingMetadata'] = meta.toJson();
    updatedMetadata['category'] = meta.category;
    updatedMetadata['fittingCategory'] = meta.category;
    updatedMetadata['product'] = meta.product;
    updatedMetadata['fittingProduct'] = meta.product;
    updatedMetadata['variantName'] = meta.variantName;
    updatedMetadata['fittingVariant'] = meta.variantName;
    updatedMetadata['isCmsProduct'] = true;
    updatedMetadata['cmsWorkflow'] = {'stage': 'manufacturing_definition', 'stageIndex': 1};
    updatedMetadata['cms_product_contract'] = {
      'productType': contract.productType,
      'variationName': contract.variationName,
      'displayName': contract.displayName,
    };
    if (updatedMetadata['cmsTemplate'] is Map) {
      final cms = Map<String, dynamic>.from(updatedMetadata['cmsTemplate'] as Map);
      cms['category'] = meta.category;
      cms['productType'] = contract.productType;
      cms['variation'] = contract.variationName;
      updatedMetadata['cmsTemplate'] = cms;
    }
    widget.viewModel.updateDocument(
      widget.viewModel.document.copyWith(
        itemName: updatedName.isNotEmpty ? updatedName : widget.viewModel.document.itemName,
        productType: contract.productType,
        metadata: updatedMetadata,
      ),
    );
    widget.viewModel.saveActiveFileDirectIfPossible();

    if (widget.onClose != null) {
      widget.onClose!();
    } else if (Navigator.canPop(context)) {
      Navigator.of(context).pop();
    }
    widget.viewModel.setFittingInspectorOpen(false);

    // Launch clean autonomous CMS discovery pipeline
    widget.viewModel.startCleanCmsDiscovery(contract: contract);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Declared as CMS Product: ${contract.displayName} — Starting 3D Channel Discovery...'),
        backgroundColor: const Color(0xFF0284C7),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _handleLaunchTeachScaling() {
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
    widget.viewModel.startTeachScaling();
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
        height: 590,
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 620),
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
                        color: (widget.viewModel.hasVerifiedCmsTemplate
                                ? const Color(0xFF059669)
                                : const Color(0xFF0284C7))
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        widget.viewModel.hasVerifiedCmsTemplate ? Icons.verified : Icons.straighten,
                        color: widget.viewModel.hasVerifiedCmsTemplate
                            ? const Color(0xFF059669)
                            : const Color(0xFF0284C7),
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 6,
                            children: [
                              Text(
                                widget.viewModel.hasVerifiedCmsTemplate
                                    ? 'DSF Fitting & Template Inspector'
                                    : 'DSF Fitting Inspector',
                                style: const TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (widget.viewModel.hasVerifiedCmsTemplate)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFECFDF5),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: const Color(0xFF10B981)),
                                  ),
                                  child: const Text(
                                    'Stage 7 Verified ✓',
                                    style: TextStyle(
                                      color: Color(0xFF059669),
                                      fontSize: 9.0,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              if (widget.onDragHeader != null)
                                const Icon(Icons.drag_indicator, size: 14, color: Color(0xFF94A3B8)),
                            ],
                          ),
                          const SizedBox(height: 1),
                          Text(
                            widget.viewModel.hasVerifiedCmsTemplate
                                ? 'Stage 7 Verified CMS template. Review port kinematics, cross section, and launch scaling.'
                                : 'Classify fitting and review Width (W) & Height (H) port dimensions.',
                            style: const TextStyle(color: Color(0xFF64748B), fontSize: 10.5),
                          ),
                        ],
                      ),
                    ),
                    // Ports (2D/3D) Annotations Toggle
                    OutlinedButton.icon(
                      onPressed: () {
                        widget.viewModel.toggleCmsPortHighlights();
                        setState(() {});
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: widget.viewModel.showCmsPortHighlights
                            ? const Color(0xFF0D9488)
                            : const Color(0xFF64748B),
                        side: BorderSide(
                          color: widget.viewModel.showCmsPortHighlights
                              ? const Color(0xFF0D9488)
                              : const Color(0xFFCBD5E1),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      icon: Icon(
                        widget.viewModel.showCmsPortHighlights ? Icons.visibility : Icons.visibility_off_outlined,
                        size: 13,
                      ),
                      label: Text(
                        widget.viewModel.showCmsPortHighlights ? 'Ports (2D/3D): ON' : 'Ports (2D/3D): OFF',
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // W×H Tags Visibility Toggle
                    OutlinedButton.icon(
                      onPressed: () {
                        widget.viewModel.togglePortOpeningBadges();
                        setState(() {});
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: widget.viewModel.showPortOpeningBadges
                            ? const Color(0xFF0284C7)
                            : const Color(0xFF64748B),
                        side: BorderSide(
                          color: widget.viewModel.showPortOpeningBadges
                              ? const Color(0xFF0284C7)
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
                    // A. Product Identity, Classification & Sheet Metal Thickness
                    _buildSectionHeader('1. PRODUCT IDENTITY & CATALOG CLASSIFICATION', Icons.inventory_2_outlined),
                    const SizedBox(height: 8),
                    Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFCBD5E1), width: 1),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.edit_note, size: 18, color: Color(0xFF0284C7)),
                          const SizedBox(width: 8),
                          const Text(
                            'Product Name:',
                            style: TextStyle(color: Color(0xFF475569), fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _itemNameController,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                              decoration: const InputDecoration(
                                hintText: 'Enter product name or part number...',
                                hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(vertical: 8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
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

                    // B. Global Properties & Manufacturing Info Grid
                    _buildGlobalPropertiesGrid(),
                    const SizedBox(height: 8),

                    // B2. Analyzed Geometry Banner
                    _buildAnalyzedInfoBanner(),
                    const SizedBox(height: 12),

                    // B3. CMS Product Declaration Banner & Toggle
                    if (!widget.viewModel.hasVerifiedCmsTemplate) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: _isDeclaredCms ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _isDeclaredCms ? const Color(0xFF86EFAC) : const Color(0xFFCBD5E1),
                            width: 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _isDeclaredCms ? Icons.auto_awesome : Icons.layers_outlined,
                              size: 18,
                              color: _isDeclaredCms ? const Color(0xFF059669) : const Color(0xFF64748B),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        'Declare as CMS Product Fitting',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                          color: _isDeclaredCms ? const Color(0xFF166534) : const Color(0xFF334155),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: _isDeclaredCms ? const Color(0xFFDCFCE7) : const Color(0xFFE2E8F0),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          _isDeclaredCms ? 'CMS ACTIVE' : 'NON-CMS (CAD)',
                                          style: TextStyle(
                                            fontSize: 9.0,
                                            fontWeight: FontWeight.bold,
                                            color: _isDeclaredCms ? const Color(0xFF15803D) : const Color(0xFF64748B),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _isDeclaredCms
                                        ? 'Declared as CMS ${_selectedProduct != 'None' ? _selectedProduct : 'Fitting'}. Enables 3D kinematic channel folding, port discovery, and template scaling.'
                                        : 'Currently opened as general CAD. Toggle ON or click Declare below to enable automatic 3D folding and template scaling.',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: _isDeclaredCms ? const Color(0xFF15803D) : const Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Switch(
                              value: _isDeclaredCms,
                              activeThumbColor: const Color(0xFF059669),
                              activeTrackColor: const Color(0xFFA7F3D0),
                              onChanged: (val) {
                                setState(() {
                                  _isDeclaredCms = val;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // C. Parameters Entry Section
                    if (widget.viewModel.hasVerifiedCmsTemplate) ...[
                      _buildSectionHeader(
                        '2. 3D TEMPLATE TOPOLOGY & VERIFIED PORTS (${widget.viewModel.verifiedCmsPorts.length} PHYSICAL OPENINGS)',
                        Icons.verified,
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Baseline CMS template definition complete. Port dimensions and global properties are displayed below (info only).',
                        style: TextStyle(color: Color(0xFF059669), fontSize: 10, fontWeight: FontWeight.w600),
                      ),
                    ] else ...[
                      _buildSectionHeader(
                        '2. PORT PARAMETERS ($portCount OPENING${portCount > 1 ? 'S' : ''})',
                        Icons.straighten,
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Port dimensions and geometry specifications displayed below (info only).',
                        style: TextStyle(color: Color(0xFF64748B), fontSize: 10),
                      ),
                    ],
                    const SizedBox(height: 8),

                    _buildPortCardsSection(portCount),
                    if (_isTrayOrLadder && _isBendFitting) _buildBendRadiusInfoCard(),
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, size: 14, color: Color(0xFF0284C7)),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Live dimensions, bend angles, coupler flaps, and perforations are managed via the CMS Parameter Inspector.',
                              style: TextStyle(fontSize: 10.5, color: Color(0xFF475569)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),
            const Divider(color: Color(0xFFE2E8F0), height: 1),
            const SizedBox(height: 10),

            // 3. Bottom Action Bar
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
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
                if (widget.viewModel.hasVerifiedCmsTemplate)
                  ElevatedButton.icon(
                    onPressed: _handleLaunchTeachScaling,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      elevation: 1,
                    ),
                    icon: const Icon(Icons.tune, size: 15),
                    label: const Text(
                      'Teach Scaling (Phase 2) →',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                if (!widget.viewModel.hasVerifiedCmsTemplate)
                  ElevatedButton.icon(
                    onPressed: _handleDeclareAsCmsProduct,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      elevation: 1,
                    ),
                    icon: const Icon(Icons.auto_awesome, size: 15),
                    label: const Text(
                      'Declare as CMS Product & Discover 3D →',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ElevatedButton.icon(
                  onPressed: _handleSaveParametersOnly,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.viewModel.hasVerifiedCmsTemplate ? const Color(0xFF059669) : const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    elevation: 1,
                  ),
                  icon: const Icon(Icons.check, size: 15),
                  label: Text(
                    widget.viewModel.hasVerifiedCmsTemplate ? 'Save Template to DSF' : 'Save Parameters to DSF',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
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

  bool get _isBendFitting {
    final prod = _selectedProduct.toLowerCase();
    final variant = _selectedVariantName.toLowerCase();
    final docType = (widget.viewModel.detectedFittingMetadata?.product ?? '').toLowerCase();
    final item = (_itemNameController.text.isNotEmpty ? _itemNameController.text : widget.viewModel.document.itemName).toLowerCase();
    return prod.contains('bend') || variant.contains('bend') || docType.contains('bend') || item.contains('bend');
  }

  bool get _isTrayOrLadder {
    final cat = _selectedCategory.toLowerCase();
    final prod = _selectedProduct.toLowerCase();
    final variant = _selectedVariantName.toLowerCase();
    final item = (_itemNameController.text.isNotEmpty ? _itemNameController.text : widget.viewModel.document.itemName).toLowerCase();
    final docType = (widget.viewModel.detectedFittingMetadata?.product ?? widget.viewModel.document.productType).toLowerCase();
    final full = '$cat $prod $variant $item $docType';
    if (full.contains('trunk') || full.contains('trunking')) return false;
    return full.contains('tray') || full.contains('ladder');
  }

  Widget _buildBendRadiusInfoCard() {
    final curRadius = double.tryParse(_controllers['radius']?.text ?? '') ??
        (_currentParams['radius'] ?? 180.0);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFBAE6FD)),
      ),
      child: Row(
        children: [
          const Icon(Icons.rounded_corner, size: 16, color: Color(0xFF0284C7)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Inside Throat Bend Radius (Tray/Ladder)',
              style: TextStyle(
                color: Color(0xFF0369A1),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF0284C7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${curRadius.toStringAsFixed(0)} mm',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlobalPropertiesGrid() {
    final doc = widget.viewModel.document;
    final thk = double.tryParse(_thicknessController.text) ?? doc.material.thicknessMm;
    final w = _analyzed['overallWidth'] ?? 0.0;
    final h = _analyzed['overallHeight'] ?? 0.0;
    final areaSqM = (w * h) / 1e6;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildPropInfoTile(
                  icon: Icons.layers_outlined,
                  label: 'Material',
                  value: doc.material.name,
                  subtext: 'Grade: ${doc.material.materialGrade.isNotEmpty ? doc.material.materialGrade : 'Standard'}',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildPropInfoTile(
                  icon: Icons.line_weight,
                  label: 'Sheet Thickness',
                  value: '${thk.toStringAsFixed(1)} mm',
                  subtext: 'Density: ${doc.material.densityKgM3.toStringAsFixed(0)} kg/m³',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildPropInfoTile(
                  icon: Icons.crop_free,
                  label: 'Flat Blank Size',
                  value: '${w > 0 ? w.toStringAsFixed(1) : '--'} × ${h > 0 ? h.toStringAsFixed(1) : '--'} mm',
                  subtext: areaSqM > 0 ? 'Area: ${areaSqM.toStringAsFixed(3)} m²' : 'Area: --',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildPropInfoTile(
                  icon: Icons.architecture,
                  label: 'Bends & Folds',
                  value: '${doc.bends.length} Fold Lines',
                  subtext: 'K-Factor: ${doc.material.kFactor.toStringAsFixed(2)}',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildPropInfoTile(
                  icon: Icons.grid_on_outlined,
                  label: 'Punches & Slots',
                  value: '${doc.punches.length} Punches',
                  subtext: '${doc.perforationPatterns.length} Perforations',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildPropInfoTile(
                  icon: Icons.polyline_outlined,
                  label: 'Outer Boundary',
                  value: '${doc.outerContour.length} Vertices',
                  subtext: 'Type: 2D Flat Blank',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPropInfoTile({
    required IconData icon,
    required String label,
    required String value,
    required String subtext,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: const Color(0xFF0284C7)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 11.5, color: Color(0xFF0F172A), fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            subtext,
            style: const TextStyle(fontSize: 9.5, color: Color(0xFF94A3B8)),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildPortCardsSection(int portCount) {
    final verifiedPorts = widget.viewModel.verifiedCmsPorts;
    if (verifiedPorts.isNotEmpty) {
      final contract = widget.viewModel.cmsGuidedController.state.contract ?? CmsProductContract.bend45;
      final thk = double.tryParse(_thicknessController.text) ?? widget.viewModel.document.material.thicknessMm;
      final allBends = widget.viewModel.document.bends;
      final wallCount = allBends.where((b) => b.role == BendLineRole.bend).length;
      final flangeCount = allBends.where((b) => b.role == BendLineRole.flange).length;
      final couplers = widget.viewModel.document.punches.where((p) => p.isCoupler).length;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CmsChannelTopologyPictograph(
            contract: contract,
            ports: verifiedPorts,
            sheetThickness: thk,
            flangeMm: _flangeMm,
            bendCount: allBends.length,
            wallCount: wallCount > 0 ? wallCount : null,
            flangeCount: flangeCount > 0 ? flangeCount : null,
            couplerCount: couplers,
            onLaunchTeachScaling: _handleLaunchTeachScaling,
          ),
          _buildVerifiedPortCards(verifiedPorts),
        ],
      );
    }

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

  Widget _buildVerifiedPortCards(List<CmsPhysicalPort> ports) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            const Text(
              'VERIFIED 3D PHYSICAL PORT PARAMETERS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF64748B),
                letterSpacing: 0.5,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: const Color(0xFF10B981)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline, size: 12, color: Color(0xFF059669)),
                  SizedBox(width: 4),
                  Text(
                    'Topology Locked (Phase 1 Complete)',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (ports.length >= 3) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _isLinkedPorts = true),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: _isLinkedPorts ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: _isLinkedPorts
                            ? [const BoxShadow(color: Color(0x10000000), blurRadius: 2, offset: Offset(0, 1))]
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.link,
                            size: 13,
                            color: _isLinkedPorts ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Equal (Linked Ports)',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: _isLinkedPorts ? FontWeight.bold : FontWeight.w500,
                              color: _isLinkedPorts ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _isLinkedPorts = false),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: !_isLinkedPorts ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: !_isLinkedPorts
                            ? [const BoxShadow(color: Color(0x10000000), blurRadius: 2, offset: Offset(0, 1))]
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.link_off,
                            size: 13,
                            color: !_isLinkedPorts ? const Color(0xFF7C3AED) : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Unequal (Independent Ports)',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: !_isLinkedPorts ? FontWeight.bold : FontWeight.w500,
                              color: !_isLinkedPorts ? const Color(0xFF7C3AED) : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: ports.asMap().entries.map((entry) {
            final idx = entry.key;
            final port = entry.value;
            final isFirst = idx == 0;
            final accentColor = idx == 0
                ? const Color(0xFF0284C7)
                : (idx == 1 ? const Color(0xFF0D9488) : const Color(0xFF7C3AED));

            return Expanded(
              child: Container(
                margin: EdgeInsets.only(left: isFirst ? 0 : 8, right: entry.key < ports.length - 1 ? 8 : 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: accentColor.withValues(alpha: 0.4), width: 1.2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Port ${port.index} (${port.index == 1 ? 'Inlet / Opening 1' : 'Outlet / Opening ${port.index}'})',
                            style: TextStyle(color: accentColor, fontSize: 11, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFFBBF7D0)),
                          ),
                          child: const Text(
                            '✓ 3D Mouth',
                            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Normal: [${port.normal.x.toStringAsFixed(2)}, ${port.normal.y.toStringAsFixed(2)}, ${port.normal.z.toStringAsFixed(2)}]',
                      style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 8),

                    // Width Row
                    _buildVerifiedParamField(
                      label: 'Width (W)',
                      key: 'port${port.index}Width',
                      val: port.width,
                      accentColor: accentColor,
                    ),
                    const SizedBox(height: 6),

                    // Height Row
                    _buildVerifiedParamField(
                      label: 'Height (H)',
                      key: 'port${port.index}Height',
                      val: port.height,
                      accentColor: accentColor,
                    ),
                    const SizedBox(height: 8),

                    // Area & Flange metrics
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Area: ${(port.width * port.height).toStringAsFixed(0)} mm²',
                            style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                          ),
                          Text(
                            'Lip: ${port.flange.toStringAsFixed(0)} mm',
                            style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildVerifiedParamField({
    required String label,
    required String key,
    required double val,
    required Color accentColor,
  }) {
    return Row(
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
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  val.toStringAsFixed(0),
                  style: const TextStyle(color: Color(0xFF0F172A), fontSize: 11.5, fontWeight: FontWeight.bold),
                ),
                const Text('mm', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
              ],
            ),
          ),
        ),
      ],
    );
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
