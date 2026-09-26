// =============================================================================
// dds_workspace_screen.dart
//
// Technical Data Sheet (TDS) Main Authoring Workspace Screen.
// Provides a unified, client-approval-oriented workspace for authoring .dds files:
// 1. Top Bar: Document Control, Revision, Status, Import Excel, Save/Open .dds.
// 2. Left Navigator: Sheet & Product Index (Cover Schedule + Product Sheets).
// 3. Center Canvas: Interactive A4/A3 Paper Canvas with ISO 7200 title block.
// 4. Right Inspector: Live Tabular Parameter Editor & Takeoff, ISO 7200 metadata,
//    and Excel order traceability.
// =============================================================================

import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../models/dsf_document.dart';
import '../../../models/dds/dds_annotation.dart';
import '../../../models/dds/dds_document.dart';
import '../../../models/dds/dds_product_instance.dart';
import '../../../models/dds/dds_sheet.dart';
import '../../../engine/dds/dds_instance_evaluator.dart';
import '../../../engine/dds/dds_template_resolver.dart';
import '../../../engine/dds/excel_order_importer.dart';
import '../../../services/studio_file_service.dart';
import 'dds_paper_canvas.dart';
import 'dds_parameter_table.dart';
import 'dds_template_library_dialog.dart';

class DdsWorkspaceScreen extends StatefulWidget {
  final DdsDocument? initialDocument;
  final VoidCallback? onExit;
  final void Function(DsfDocument dsfDocument)? onOpenInEditor;

  const DdsWorkspaceScreen({
    super.key,
    this.initialDocument,
    this.onExit,
    this.onOpenInEditor,
  });

  @override
  State<DdsWorkspaceScreen> createState() => _DdsWorkspaceScreenState();
}

class _DdsWorkspaceScreenState extends State<DdsWorkspaceScreen> with SingleTickerProviderStateMixin {
  late DdsDocument _document;
  int _activeSheetIndex = 0;
  bool _isRightPanelOpen = true;
  int _inspectorTabIndex = 0; // 0: Parameters, 1: Document Control, 2: Order Traceability

  // Active markup authoring tool
  DdsMarkupTool _activeMarkupTool = DdsMarkupTool.select;
  String? _selectedAnnotationId;

  // Cache of evaluated instances: instanceId -> EvaluatedDdsInstance
  final Map<String, EvaluatedDdsInstance> _evaluatedCache = {};
  bool _isEvaluating = false;

  @override
  void initState() {
    super.initState();
    _document = widget.initialDocument ?? _createDefaultDocument();
    _evaluateActiveSheet();
  }

  DdsDocument _createDefaultDocument() {
    final doc = DdsDocument.create(
      documentTitle: 'Hospital Cable Management System',
      documentNumber: 'TDS-2026-001',
      projectName: 'Main Hospital Building - Level 3 Services',
      client: 'Apex Health Infrastructure Group',
      consultant: 'Arup Engineering Consultants',
      contractor: 'Drake & Scull Engineering',
      preparedBy: 'Lead Mechanical Engineer',
    );

    // Seed with a standard Straight Reducer
    final ref = DdsTemplateResolver.createReference('trunking_reducer');
    final instance = DdsProductInstance(
      instanceId: 'inst_001',
      productName: 'Straight Reducer 150×100 to 75×50',
      productCode: 'RED-150-75',
      orderLine: const DdsOrderLine(
        orderNumber: 'PO-88210',
        lineNumber: '001',
        customerItemReference: 'RED-150-75',
        quantity: 12,
        customerDescription: 'Straight Reducer 150x100 to 75x50 mm',
        remarks: 'Transition at riser shaft B',
      ),
      templateReference: ref,
      instanceParameters: {
        'port1_width': 150.0,
        'port1_height': 100.0,
        'port2_width': 75.0,
        'port2_height': 50.0,
      },
      coverConfiguration: const DdsCoverConfig(
        included: true,
        placementMode3D: 'exploded',
      ),
      material: 'Pre-Galvanized Mild Steel DX51D',
      finish: 'Z275 Mill Galvanized Coating',
    );

    return doc.addProductInstance(instance, sheetTitle: 'RED-150-75 — Straight Reducer');
  }

  DdsSheet get _currentSheet {
    if (_activeSheetIndex < 0 || _activeSheetIndex >= _document.sheets.length) {
      return _document.coverScheduleSheet;
    }
    return _document.sheets[_activeSheetIndex];
  }

  DdsProductInstance? get _currentProductInstance {
    final sheet = _currentSheet;
    if (sheet.isCoverPage || sheet.productInstanceId == null) return null;
    return _document.findInstance(sheet.productInstanceId);
  }

  void _evaluateActiveSheet() {
    final instance = _currentProductInstance;
    if (instance == null) {
      setState(() {});
      return;
    }

    if (_evaluatedCache.containsKey(instance.instanceId)) {
      setState(() {});
      return;
    }

    _evaluateInstance(instance);
  }

  Future<void> _evaluateInstance(DdsProductInstance instance) async {
    setState(() => _isEvaluating = true);

    try {
      final baselineDoc = await DdsTemplateResolver.resolveTemplateAsync(instance.templateReference);
      if (baselineDoc != null) {
        final evaluated = DdsInstanceEvaluator.evaluate(
          instance: instance,
          baselineDoc: baselineDoc,
        );
        _evaluatedCache[instance.instanceId] = evaluated;

        // Sync calculated takeoff back to instance
        final updatedInstance = instance.copyWith(
          calculatedTakeoff: evaluated.calculatedTakeoff,
        );
        _updateInstanceInDocument(updatedInstance, triggerEvaluation: false);
      }
    } catch (e) {
      debugPrint('Error evaluating DDS instance: $e');
    } finally {
      if (mounted) {
        setState(() => _isEvaluating = false);
      }
    }
  }

  void _updateInstanceInDocument(DdsProductInstance updatedInstance, {bool triggerEvaluation = true}) {
    final updatedInstances = _document.productInstances.map((i) {
      return i.instanceId == updatedInstance.instanceId ? updatedInstance : i;
    }).toList();

    var updatedDoc = _document.copyWith(productInstances: updatedInstances);
    updatedDoc = updatedDoc.updateToc();

    setState(() {
      _document = updatedDoc;
    });

    if (triggerEvaluation) {
      _evaluatedCache.remove(updatedInstance.instanceId);
      _evaluateInstance(updatedInstance);
    }
  }

  // ===========================================================================
  // Top-Level Document Actions (Import Excel, Save, Open)
  // ===========================================================================

  Future<void> _handleImportExcel() async {
    try {
      final List<PlatformFile> files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );

      if (files.isEmpty) return;

      final file = files.first;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return;

      final preview = ExcelOrderImporter.previewWorkbook(bytes, fileName: file.name);
      if (!mounted) return;

      // Show Import Confirmation Dialog with Preview
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: Row(
            children: [
              const Icon(Icons.table_chart, color: Color(0xFF38BDF8)),
              const SizedBox(width: 8.0),
              Text('Import Order List (${file.name})', style: const TextStyle(color: Colors.white, fontSize: 15.0)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Detected Worksheets: ${preview.sheetNames.join(", ")}', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12.0)),
              const SizedBox(height: 8.0),
              Text(
                'This will import all order line items, resolve CMS templates, and generate a new Technical Data Sheet submittal binder.',
                style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12.0),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Proceed with Import', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      final importResult = ExcelOrderImporter.importWorkbook(
        bytes: bytes,
        fileName: file.name,
      );

      setState(() {
        _document = importResult.document;
        _activeSheetIndex = 0;
        _evaluatedCache.clear();
      });

      _evaluateActiveSheet();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imported ${importResult.summary.templatesMatched} products successfully from ${file.name}!',
          ),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    } catch (e) {
      debugPrint('Error importing Excel: $e');
    }
  }

  Future<void> _handleSaveDds() async {
    final jsonStr = const JsonEncoder.withIndent('  ').convert(_document.toJson());
    final defaultFileName = '${_document.projectInfo.documentNumber}.dds';

    final path = await StudioFileService.saveFileAs(
      fileName: defaultFileName,
      content: jsonStr,
      dialogTitle: 'Save Technical Data Sheet (.dds)',
    );

    if (path != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Technical Data Sheet saved: $path'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    }
  }

  Future<void> _handleOpenDds() async {
    try {
      final rawFiles = await StudioFileService.pickRawFiles();
      if (rawFiles.isEmpty) return;

      final file = rawFiles.first;
      final jsonMap = jsonDecode(file.content) as Map<String, dynamic>;
      final openedDoc = DdsDocument.fromJson(jsonMap);

      setState(() {
        _document = openedDoc;
        _activeSheetIndex = 0;
        _evaluatedCache.clear();
      });

      _evaluateActiveSheet();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Opened TDS Document: ${_document.projectInfo.documentNumber} (${_document.totalSheets} sheets)'),
          backgroundColor: const Color(0xFF0284C7),
        ),
      );
    } catch (e) {
      debugPrint('Error opening DDS file: $e');
    }
  }

  void _handleOpenTemplateLibrary() {
    DdsTemplateLibraryDialog.show(
      context,
      activeDocument: _document,
      onAddToDds: (newInstance, {bool switchToEditor = false}) {
        final updatedDoc = _document.addProductInstance(newInstance, sheetTitle: newInstance.productName);
        setState(() {
          _document = updatedDoc;
          if (switchToEditor) {
            _activeSheetIndex = updatedDoc.sheets.length - 1;
            _inspectorTabIndex = 0; // Go to Parameter Editor
            _isRightPanelOpen = true;
          }
        });
        _evaluateActiveSheet();
      },
      onOpenInEditor: (dsfDoc) {
        if (widget.onOpenInEditor != null) {
          widget.onOpenInEditor!(dsfDoc);
          if (widget.onExit != null) widget.onExit!();
        }
      },
    );
  }

  void _handleAnnotationsChanged(List<DdsAnnotation> updatedAnnotations) {
    final current = _currentSheet;
    final updatedSheet = current.copyWith(annotations: updatedAnnotations);
    final updatedSheets = _document.sheets.map((s) {
      return s.sheetId == updatedSheet.sheetId ? updatedSheet : s;
    }).toList();

    setState(() {
      _document = _document.copyWith(sheets: updatedSheets);
    });
  }

  Widget _buildFloatingMarkupPalette() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: const Color(0xFF334155), width: 1.0),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 10.0, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildMarkupToolButton(
            tool: DdsMarkupTool.select,
            icon: Icons.near_me,
            tooltip: 'Select & Move Markup',
          ),
          const SizedBox(width: 4.0),
          _buildMarkupToolButton(
            tool: DdsMarkupTool.linearDimension,
            icon: Icons.straighten,
            tooltip: 'Linear Dimension (Click 2 points on canvas)',
          ),
          const SizedBox(width: 4.0),
          _buildMarkupToolButton(
            tool: DdsMarkupTool.leaderNote,
            icon: Icons.call_made,
            tooltip: 'Leader Callout Note (Click target then text position)',
          ),
          const SizedBox(width: 4.0),
          _buildMarkupToolButton(
            tool: DdsMarkupTool.noteBox,
            icon: Icons.note_alt_outlined,
            tooltip: 'Sheet Specification Note Box',
          ),
          const SizedBox(width: 4.0),
          _buildMarkupToolButton(
            tool: DdsMarkupTool.revisionCloud,
            icon: Icons.cloud_outlined,
            tooltip: 'Revision Cloud (Click points around area)',
          ),
          const SizedBox(width: 4.0),
          _buildMarkupToolButton(
            tool: DdsMarkupTool.approvalStamp,
            icon: Icons.verified_outlined,
            tooltip: 'Client Approval Review Stamp',
          ),
          if (_selectedAnnotationId != null) ...[
            const SizedBox(width: 6.0),
            Container(height: 20, width: 1, color: const Color(0xFF475569)),
            const SizedBox(width: 6.0),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 18),
              tooltip: 'Delete Selected Markup',
              onPressed: () {
                final currentSheet = _currentSheet;
                final list = currentSheet.annotations.where((a) => a.id != _selectedAnnotationId).toList();
                _handleAnnotationsChanged(list);
                setState(() => _selectedAnnotationId = null);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMarkupToolButton({
    required DdsMarkupTool tool,
    required IconData icon,
    required String tooltip,
  }) {
    final isSelected = _activeMarkupTool == tool;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6.0),
        onTap: () {
          setState(() {
            _activeMarkupTool = tool;
            if (tool != DdsMarkupTool.select) {
              _selectedAnnotationId = null;
            }
          });
        },
        child: Container(
          padding: const EdgeInsets.all(7.0),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF0284C7) : Colors.transparent,
            borderRadius: BorderRadius.circular(6.0),
          ),
          child: Icon(
            icon,
            size: 17,
            color: isSelected ? Colors.white : const Color(0xFF94A3B8),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // Build Method
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B132B), // Deep Blueprint Navy
      body: SafeArea(
        child: Column(
          children: [
            // Top Navigation & Document Control Header Bar
            _buildTopAppBar(),
            const Divider(height: 1, color: Color(0xFF1E293B)),

            // Main Workspace Layout: Navigator | Paper Canvas | Inspector
            Expanded(
              child: Row(
                children: [
                  // Left: Sheet & Product Index Navigator (280px)
                  _buildLeftSheetNavigator(),
                  const VerticalDivider(width: 1, color: Color(0xFF1E293B)),

                  // Center: Paper Layout Canvas
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Container(
                            color: const Color(0xFF0F172A), // Slate 900 Canvas Desk
                            padding: const EdgeInsets.all(24.0),
                            child: DdsPaperCanvas(
                              document: _document,
                              sheet: _currentSheet,
                              evaluatedInstance: _currentProductInstance != null
                                  ? _evaluatedCache[_currentProductInstance!.instanceId]
                                  : null,
                              activeMarkupTool: _activeMarkupTool,
                              selectedAnnotationId: _selectedAnnotationId,
                              onAnnotationsChanged: _handleAnnotationsChanged,
                              onAnnotationSelected: (id) => setState(() => _selectedAnnotationId = id),
                              onNextSheet: _activeSheetIndex < _document.sheets.length - 1
                                  ? () => setState(() {
                                        _activeSheetIndex++;
                                        _evaluateActiveSheet();
                                      })
                                  : null,
                              onPrevSheet: _activeSheetIndex > 0
                                  ? () => setState(() {
                                        _activeSheetIndex--;
                                        _evaluateActiveSheet();
                                      })
                                  : null,
                            ),
                          ),
                        ),

                        // Floating Interactive Markup Authoring Palette
                        Positioned(
                          top: 24,
                          left: 0,
                          right: 0,
                          child: Center(child: _buildFloatingMarkupPalette()),
                        ),

                        // Floating Sheet Navigation HUD
                        Positioned(
                          bottom: 24,
                          left: 24,
                          child: _buildFloatingNavigationHud(),
                        ),

                        // Loading Indicator
                        if (_isEvaluating)
                          Positioned(
                            top: 24,
                            left: 24,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(6.0),
                                border: Border.all(color: const Color(0xFF38BDF8)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8)),
                                  ),
                                  SizedBox(width: 8.0),
                                  Text(
                                    'Evaluating CMS Kinematics & Cover...',
                                    style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11.0),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Right: Inspector / Parameter Editor (380px)
                  if (_isRightPanelOpen) ...[
                    const VerticalDivider(width: 1, color: Color(0xFF1E293B)),
                    SizedBox(
                      width: 380,
                      child: _buildRightInspectorPanel(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // Top App Bar
  // ===========================================================================

  Widget _buildTopAppBar() {
    final proj = _document.projectInfo;

    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      color: const Color(0xFF0F172A),
      child: Row(
        children: [
          // Exit button
          if (widget.onExit != null) ...[
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Color(0xFF94A3B8), size: 20),
              onPressed: widget.onExit,
              tooltip: 'Return to Studio',
            ),
            const SizedBox(width: 8.0),
          ],

          // App Mark
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            decoration: BoxDecoration(
              color: const Color(0xFF0284C7).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4.0),
              border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.5)),
            ),
            child: const Text(
              'TDS / .DDS',
              style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11.0),
            ),
          ),
          const SizedBox(width: 12.0),

          // Title & Doc Number
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Text(
                      proj.documentTitle,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.0),
                    ),
                    const SizedBox(width: 8.0),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 1.0),
                      decoration: BoxDecoration(
                        color: const Color(0xFF334155),
                        borderRadius: BorderRadius.circular(3.0),
                      ),
                      child: Text('REV ${proj.revision}', style: const TextStyle(color: Colors.white, fontSize: 10.0)),
                    ),
                  ],
                ),
                Text(
                  '${proj.documentNumber} • ${proj.client.isNotEmpty ? proj.client : "Standard Client"}',
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.0),
                ),
              ],
            ),
          ),

          // Action Buttons: Template Library, Import Excel, Save, Open
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFF59E0B),
              side: const BorderSide(color: Color(0xFFF59E0B)),
              padding: const EdgeInsets.symmetric(horizontal: 11.0, vertical: 8.0),
            ),
            icon: const Icon(Icons.collections_bookmark, size: 16),
            label: const Text('Template Library', style: TextStyle(fontSize: 12.0)),
            onPressed: _handleOpenTemplateLibrary,
          ),
          const SizedBox(width: 8.0),

          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            ),
            icon: const Icon(Icons.table_chart, size: 16),
            label: const Text('Import Excel (.xlsx)', style: TextStyle(fontSize: 12.0)),
            onPressed: _handleImportExcel,
          ),
          const SizedBox(width: 8.0),

          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF38BDF8),
              side: const BorderSide(color: Color(0xFF0284C7)),
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            ),
            icon: const Icon(Icons.file_open_outlined, size: 16),
            label: const Text('Open .dds', style: TextStyle(fontSize: 12.0)),
            onPressed: _handleOpenDds,
          ),
          const SizedBox(width: 8.0),

          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            ),
            icon: const Icon(Icons.save_outlined, size: 16),
            label: const Text('Save .dds', style: TextStyle(fontSize: 12.0)),
            onPressed: _handleSaveDds,
          ),
          const SizedBox(width: 12.0),

          // Toggle Inspector
          IconButton(
            icon: Icon(
              _isRightPanelOpen ? Icons.dock : Icons.dock_outlined,
              color: _isRightPanelOpen ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8),
            ),
            onPressed: () => setState(() => _isRightPanelOpen = !_isRightPanelOpen),
            tooltip: 'Toggle Parameters Inspector',
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // Left Sheet Navigator
  // ===========================================================================

  Widget _buildLeftSheetNavigator() {
    return Container(
      width: 280,
      color: const Color(0xFF0F172A),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
            color: const Color(0xFF1E293B),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'SHEET NAVIGATOR',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11.0,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
                Text(
                  '${_document.totalSheets} Sheets',
                  style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11.0, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF334155)),

          // Add Fitting from Library Action Button
          Padding(
            padding: const EdgeInsets.fromLTRB(12.0, 10.0, 12.0, 6.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  padding: const EdgeInsets.symmetric(vertical: 9.0),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                ),
                icon: const Icon(Icons.add_circle_outline, size: 15, color: Colors.white),
                label: const Text(
                  'Add from Library',
                  style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                ),
                onPressed: _handleOpenTemplateLibrary,
              ),
            ),
          ),
          const Divider(height: 1, color: Color(0xFF1E293B)),

          // Sheet List
          Expanded(
            child: ListView.separated(
              itemCount: _document.sheets.length,
              separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFF1E293B)),
              itemBuilder: (context, idx) {
                final sheet = _document.sheets[idx];
                final isSelected = idx == _activeSheetIndex;
                final inst = _document.findInstance(sheet.productInstanceId);

                return ListTile(
                  dense: true,
                  selected: isSelected,
                  selectedTileColor: const Color(0xFF0284C7).withValues(alpha: 0.2),
                  leading: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(4.0),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      sheet.sheetNumber.toString().padLeft(2, '0'),
                      style: TextStyle(
                        color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                        fontSize: 11.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    sheet.isCoverPage ? 'Transmittal & Schedule' : (inst?.productName ?? sheet.title),
                    style: TextStyle(
                      color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
                      fontSize: 12.0,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    sheet.isCoverPage
                        ? '${_document.productInstances.length} Products'
                        : 'Ref: ${inst?.productCode ?? "—"} • Qty: ${inst?.orderLine?.quantity ?? 1}',
                    style: TextStyle(
                      color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF64748B),
                      fontSize: 10.0,
                    ),
                  ),
                  onTap: () {
                    setState(() => _activeSheetIndex = idx);
                    _evaluateActiveSheet();
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // Right Inspector Panel
  // ===========================================================================

  Widget _buildRightInspectorPanel() {
    final instance = _currentProductInstance;

    return Container(
      color: const Color(0xFF0F172A),
      child: Column(
        children: [
          // Inspector Tab Bar
          Container(
            color: const Color(0xFF1E293B),
            child: Row(
              children: [
                _buildInspectorTab(0, 'Parameters', Icons.tune),
                _buildInspectorTab(1, 'Doc Control', Icons.badge_outlined),
                _buildInspectorTab(2, 'Traceability', Icons.hub_outlined),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF334155)),

          // Tab Content
          Expanded(
            child: _buildInspectorTabContent(instance),
          ),
        ],
      ),
    );
  }

  Widget _buildInspectorTab(int index, String title, IconData icon) {
    final isSelected = _inspectorTabIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _inspectorTabIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10.0),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? const Color(0xFF38BDF8) : Colors.transparent,
                width: 2.0,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8)),
              const SizedBox(width: 4.0),
              Text(
                title,
                style: TextStyle(
                  color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                  fontSize: 11.0,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInspectorTabContent(DdsProductInstance? instance) {
    switch (_inspectorTabIndex) {
      case 0:
        if (instance == null) {
          return const Center(
            child: Text(
              'Select a product sheet to edit parameters.',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12.0),
            ),
          );
        }
        return DdsParameterTable(
          instance: instance,
          onInstanceChanged: _updateInstanceInDocument,
        );

      case 1:
        return _buildDocumentControlForm();

      case 2:
        return _buildOrderTraceabilityView(instance);

      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildDocumentControlForm() {
    final proj = _document.projectInfo;

    return ListView(
      padding: const EdgeInsets.all(14.0),
      children: [
        _buildTextField('Document Title', proj.documentTitle, (v) {
          setState(() => _document = _document.copyWith(projectInfo: proj.copyWith(documentTitle: v)));
        }),
        _buildTextField('Document Number', proj.documentNumber, (v) {
          setState(() => _document = _document.copyWith(projectInfo: proj.copyWith(documentNumber: v)));
        }),
        _buildTextField('Revision Index', proj.revision, (v) {
          setState(() => _document = _document.copyWith(projectInfo: proj.copyWith(revision: v)));
        }),
        _buildTextField('Client Name', proj.client, (v) {
          setState(() => _document = _document.copyWith(projectInfo: proj.copyWith(client: v)));
        }),
        _buildTextField('Project Name', proj.projectName, (v) {
          setState(() => _document = _document.copyWith(projectInfo: proj.copyWith(projectName: v)));
        }),
        _buildTextField('Consultant', proj.consultant, (v) {
          setState(() => _document = _document.copyWith(projectInfo: proj.copyWith(consultant: v)));
        }),
        _buildTextField('Contractor', proj.contractor, (v) {
          setState(() => _document = _document.copyWith(projectInfo: proj.copyWith(contractor: v)));
        }),
        _buildTextField('Prepared By', proj.preparedBy, (v) {
          setState(() => _document = _document.copyWith(projectInfo: proj.copyWith(preparedBy: v)));
        }),
        _buildTextField('Approved By', proj.approvedBy, (v) {
          setState(() => _document = _document.copyWith(projectInfo: proj.copyWith(approvedBy: v)));
        }),
      ],
    );
  }

  Widget _buildTextField(String label, String value, ValueChanged<String> onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.0, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4.0),
          TextFormField(
            initialValue: value,
            style: const TextStyle(color: Colors.white, fontSize: 12.0),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
              filled: true,
              fillColor: const Color(0xFF1E293B),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(4.0), borderSide: const BorderSide(color: Color(0xFF334155))),
            ),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildOrderTraceabilityView(DdsProductInstance? instance) {
    final order = instance?.orderLine;
    if (order == null) {
      return const Center(
        child: Text(
          'No Excel order metadata for this item.',
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12.0),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(14.0),
      children: [
        _buildTraceItem('Order Number', order.orderNumber),
        _buildTraceItem('Order Line No', order.lineNumber),
        _buildTraceItem('Customer Item Ref', order.customerItemReference),
        _buildTraceItem('Customer Description', order.customerDescription),
        _buildTraceItem('Order Quantity', '${order.quantity} PCS'),
        _buildTraceItem('Source Worksheet', order.sourceSheet ?? 'N/A'),
        _buildTraceItem('Source Row in Excel', order.sourceRow != null ? '${order.sourceRow}' : 'N/A'),
        _buildTraceItem('Client Remarks', order.remarks.isNotEmpty ? order.remarks : 'None'),
      ],
    );
  }

  Widget _buildTraceItem(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8.0),
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(4.0),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF64748B), fontSize: 10.0, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2.0),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 12.0, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildFloatingNavigationHud() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20.0),
        border: Border.all(color: const Color(0xFF334155)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10.0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 14, color: Colors.white),
            onPressed: _activeSheetIndex > 0
                ? () {
                    setState(() => _activeSheetIndex--);
                    _evaluateActiveSheet();
                  }
                : null,
          ),
          Text(
            'Sheet ${_activeSheetIndex + 1} of ${_document.totalSheets}',
            style: const TextStyle(color: Colors.white, fontSize: 12.0, fontWeight: FontWeight.bold),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white),
            onPressed: _activeSheetIndex < _document.sheets.length - 1
                ? () {
                    setState(() => _activeSheetIndex++);
                    _evaluateActiveSheet();
                  }
                : null,
          ),
        ],
      ),
    );
  }
}
