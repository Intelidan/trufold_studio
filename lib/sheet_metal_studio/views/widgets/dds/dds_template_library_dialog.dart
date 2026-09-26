// =============================================================================
// dds_template_library_dialog.dart
//
// DSF Master Template Library Lister & Browser.
// Displays all .dsf files discovered in the application directory in a clean
// engineering tabular format with live 2D flat sketch and 3D isometric thumbnails.
//
// Actions:
// 1. "+ Add to DDS Set": Appends a new product sheet to the active submittal.
// 2. "Edit in TDS": Adds to DDS and switches directly to the parameter editor.
// 3. "Open in CAD Editor": Dispatches template to SheetMetalStudioViewModel.
// =============================================================================

import 'package:flutter/material.dart';

import '../../../models/dsf_document.dart';
import '../../../models/dds/dds_document.dart';
import '../../../models/dds/dds_product_instance.dart';
import '../../../engine/dds/dds_template_resolver.dart';
import '../../../engine/dds/dsf_library_service.dart';
import 'dds_drawing_painters.dart';

class DdsTemplateLibraryDialog extends StatefulWidget {
  final DdsDocument? activeDocument;
  final void Function(DdsProductInstance newInstance, {bool switchToEditor})? onAddToDds;
  final void Function(DsfDocument dsfDocument)? onOpenInEditor;

  const DdsTemplateLibraryDialog({
    super.key,
    this.activeDocument,
    this.onAddToDds,
    this.onOpenInEditor,
  });

  /// Displays the template library in an engineering modal dialog.
  static Future<void> show(
    BuildContext context, {
    DdsDocument? activeDocument,
    void Function(DdsProductInstance newInstance, {bool switchToEditor})? onAddToDds,
    void Function(DsfDocument dsfDocument)? onOpenInEditor,
  }) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
        child: DdsTemplateLibraryDialog(
          activeDocument: activeDocument,
          onAddToDds: onAddToDds,
          onOpenInEditor: onOpenInEditor,
        ),
      ),
    );
  }

  @override
  State<DdsTemplateLibraryDialog> createState() => _DdsTemplateLibraryDialogState();
}

class _DdsTemplateLibraryDialogState extends State<DdsTemplateLibraryDialog> {
  List<DsfLibraryItem> _items = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedCategory = 'All';

  final List<String> _categories = [
    'All',
    'Reducers & Transitions',
    'Tees & Branches',
    'Crosses & 4-Ways',
    'Flat Bends & Elbows',
    'Vertical Risers',
  ];

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    setState(() => _isLoading = true);
    try {
      final items = await DsfLibraryService.loadAllTemplates();
      if (mounted) {
        setState(() {
          _items = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading template library: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<DsfLibraryItem> get _filteredItems {
    return _items.where((item) {
      if (_selectedCategory != 'All' && item.category != _selectedCategory) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final match = item.displayName.toLowerCase().contains(query) ||
            item.fileName.toLowerCase().contains(query) ||
            item.templateId.toLowerCase().contains(query) ||
            item.category.toLowerCase().contains(query) ||
            item.defaultDimensions.toLowerCase().contains(query);
        if (!match) return false;
      }
      return true;
    }).toList();
  }

  void _handleAddInstance(DsfLibraryItem item, {bool switchToEditor = false}) {
    if (widget.onAddToDds == null) return;

    final baseId = item.templateId.replaceAll('trunking_', '');
    final count = (widget.activeDocument?.productInstances.length ?? 0) + 1;
    final productCode = '${baseId.toUpperCase()}-${count.toString().padLeft(3, '0')}';

    final newInstance = DdsProductInstance(
      instanceId: 'inst_${DateTime.now().millisecondsSinceEpoch}_${item.templateId}',
      productName: item.displayName,
      productCode: productCode,
      orderLine: DdsOrderLine(
        lineNumber: count.toString().padLeft(3, '0'),
        customerItemReference: productCode,
        quantity: 1,
        customerDescription: item.description,
      ),
      templateReference: DdsTemplateResolver.createReference(item.templateId),
      instanceParameters: {}, // Starts with clean template baseline
      coverConfiguration: const DdsCoverConfig(
        included: true,
        placementMode3D: 'exploded',
      ),
      material: item.document.material.materialGrade,
      finish: item.document.material.finish.name,
    );

    widget.onAddToDds!(newInstance, switchToEditor: switchToEditor);

    if (switchToEditor) {
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added "${item.displayName}" to Technical Data Sheet!'),
          backgroundColor: const Color(0xFF10B981),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1200,
      height: 780,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A), // Slate 900
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: const Color(0xFF334155), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 24.0,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // 1. Top Header Bar
          _buildHeaderBar(),
          const Divider(height: 1, color: Color(0xFF1E293B)),

          // 2. Filter & Search Controls Strip
          _buildFilterStrip(),
          const Divider(height: 1, color: Color(0xFF1E293B)),

          // 3. Tabular Template List
          Expanded(
            child: _isLoading ? _buildLoadingState() : _buildTabularView(),
          ),

          // 4. Bottom Footer Status Bar
          const Divider(height: 1, color: Color(0xFF1E293B)),
          _buildFooterBar(),
        ],
      ),
    );
  }

  // ===========================================================================
  // Header Bar
  // ===========================================================================

  Widget _buildHeaderBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 14.0),
      color: const Color(0xFF1E293B),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: const Color(0xFF0284C7).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6.0),
              border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.5)),
            ),
            child: const Icon(Icons.collections_bookmark, color: Color(0xFF38BDF8), size: 20),
          ),
          const SizedBox(width: 12.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'DSF MASTER TEMPLATE LIBRARY',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14.0,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(width: 10.0),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0369A1),
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                      child: Text(
                        '${_items.length} TEMPLATES FOUND',
                        style: const TextStyle(color: Colors.white, fontSize: 10.0, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2.0),
                const Text(
                  'Standard Cable Management System (CMS) parametric fittings residing in assets/dxf_templates/',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF94A3B8), size: 20),
            tooltip: 'Re-scan App Directory',
            onPressed: () {
              DsfLibraryService.clearCache();
              _loadTemplates();
            },
          ),
          const SizedBox(width: 8.0),
          IconButton(
            icon: const Icon(Icons.close, color: Color(0xFF94A3B8), size: 20),
            tooltip: 'Close Library',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // Filter & Search Controls
  // ===========================================================================

  Widget _buildFilterStrip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
      color: const Color(0xFF0F172A),
      child: Row(
        children: [
          // Search Input
          SizedBox(
            width: 260,
            height: 36,
            child: TextField(
              style: const TextStyle(color: Colors.white, fontSize: 12.0),
              decoration: InputDecoration(
                hintText: 'Search templates, ports, sizes...',
                hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12.0),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF64748B), size: 16),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                contentPadding: const EdgeInsets.symmetric(vertical: 0.0, horizontal: 10.0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6.0),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6.0),
                  borderSide: const BorderSide(color: Color(0xFF334155)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6.0),
                  borderSide: const BorderSide(color: Color(0xFF38BDF8)),
                ),
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),
          const SizedBox(width: 16.0),

          // Category Chips
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _categories.map((cat) {
                  final isSelected = _selectedCategory == cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(cat, style: TextStyle(fontSize: 11.5, color: isSelected ? Colors.white : const Color(0xFF94A3B8))),
                      selected: isSelected,
                      selectedColor: const Color(0xFF0284C7),
                      backgroundColor: const Color(0xFF1E293B),
                      side: BorderSide(
                        color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF334155),
                      ),
                      onSelected: (selected) {
                        if (selected) setState(() => _selectedCategory = cat);
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // Tabular Template List
  // ===========================================================================

  Widget _buildTabularView() {
    final items = _filteredItems;

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, color: Color(0xFF64748B), size: 48),
            const SizedBox(height: 12.0),
            Text(
              'No templates match "$_searchQuery"',
              style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 14.0),
            ),
            const SizedBox(height: 4.0),
            const Text(
              'Try adjusting your search query or selecting a different category filter.',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 12.0),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Table Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
          color: const Color(0xFF1E293B).withValues(alpha: 0.6),
          child: const Row(
            children: [
              SizedBox(width: 84, child: Text('2D SKETCH', style: _headerStyle)),
              SizedBox(width: 14.0),
              SizedBox(width: 84, child: Text('3D ISO VIEW', style: _headerStyle)),
              SizedBox(width: 16.0),
              Expanded(flex: 3, child: Text('TEMPLATE / PRODUCT', style: _headerStyle)),
              Expanded(flex: 3, child: Text('BASELINE SPECIFICATION', style: _headerStyle)),
              SizedBox(width: 130, child: Text('GEOMETRY TAKEOFF', style: _headerStyle)),
              SizedBox(width: 280, child: Text('ACTIONS', style: _headerStyle, textAlign: TextAlign.right)),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFF334155)),

        // Table Rows
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFF1E293B)),
            itemBuilder: (context, index) {
              final item = items[index];
              return _buildTableRow(item);
            },
          ),
        ),
      ],
    );
  }

  static const TextStyle _headerStyle = TextStyle(
    color: Color(0xFF94A3B8),
    fontSize: 10.5,
    fontWeight: FontWeight.bold,
    letterSpacing: 0.5,
  );

  Widget _buildTableRow(DsfLibraryItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. 2D Sketch Thumbnail
          Dsf2DThumbnailWidget(
            document: item.document,
            width: 84,
            height: 64,
          ),
          const SizedBox(width: 14.0),

          // 2. 3D Isometric View Thumbnail
          Dsf3DIsometricThumbnailWidget(
            mesh: item.foldedMesh,
            width: 84,
            height: 64,
          ),
          const SizedBox(width: 16.0),

          // 3. Template & Product Name
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  item.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 3.0),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 1.0),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0369A1).withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(3.0),
                        border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        item.category,
                        style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 9.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 6.0),
                    Expanded(
                      child: Text(
                        item.fileName,
                        style: const TextStyle(color: Color(0xFF64748B), fontSize: 10.5, fontFamily: 'monospace'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 4. Baseline Dimensions & Specs
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    const Icon(Icons.straighten, size: 13, color: Color(0xFF38BDF8)),
                    const SizedBox(width: 4.0),
                    Expanded(
                      child: Text(
                        item.defaultDimensions,
                        style: const TextStyle(
                          color: Color(0xFFE2E8F0),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3.0),
                Text(
                  '${item.document.material.materialGrade} • ${item.document.material.thicknessMm}mm Pre-Galv',
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5),
                ),
              ],
            ),
          ),

          // 5. Geometry Takeoff (Bends, Punches, Area, Weight)
          SizedBox(
            width: 130,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${item.bendCount} Bends • ${item.punchCount} Punches',
                  style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11.0, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2.0),
                Text(
                  '${item.surfaceAreaM2.toStringAsFixed(3)} m² • ~${item.estimatedWeightKg.toStringAsFixed(2)} kg',
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5),
                ),
              ],
            ),
          ),

          // 6. Action Buttons
          SizedBox(
            width: 280,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Button 1: Add to TDS Set
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5.0)),
                  ),
                  icon: const Icon(Icons.add, size: 14, color: Colors.white),
                  label: const Text('Add to TDS', style: TextStyle(color: Colors.white, fontSize: 11.0)),
                  onPressed: () => _handleAddInstance(item, switchToEditor: false),
                ),
                const SizedBox(width: 6.0),

                // Button 2: Edit in TDS
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF38BDF8),
                    side: const BorderSide(color: Color(0xFF0284C7)),
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5.0)),
                  ),
                  child: const Text('Edit in TDS', style: TextStyle(fontSize: 11.0)),
                  onPressed: () => _handleAddInstance(item, switchToEditor: true),
                ),
                const SizedBox(width: 6.0),

                // Button 3: Open in CAD Editor
                if (widget.onOpenInEditor != null)
                  IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF1E293B),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5.0),
                        side: const BorderSide(color: Color(0xFF334155)),
                      ),
                    ),
                    icon: const Icon(Icons.draw, size: 15, color: Color(0xFFF59E0B)),
                    tooltip: 'Open Baseline Template in 2D/3D CAD Editor',
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onOpenInEditor!(item.document);
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // Loading & Footer States
  // ===========================================================================

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF38BDF8)),
          SizedBox(height: 16.0),
          Text(
            'Scanning App Directory & Pre-folding 3D Templates...',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13.0),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterBar() {
    final count = _filteredItems.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
      color: const Color(0xFF1E293B),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Showing $count of ${_items.length} templates  •  Base Directory: assets/dxf_templates/trunking_accessories/',
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 11.0),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
