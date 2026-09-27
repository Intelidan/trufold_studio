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
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../models/cad_primitives.dart';
import '../../../models/dsf_document.dart';
import '../../../models/dds/dds_annotation.dart';
import '../../../models/dds/dds_document.dart';
import '../../../models/dds/dds_product_instance.dart';
import '../../../models/dds/dds_sheet.dart';
import '../../../engine/dds/dds_instance_evaluator.dart';
import '../../../engine/dds/dds_template_resolver.dart';
import '../../../engine/dds/excel_order_importer.dart';
import '../../../services/studio_clipboard_service.dart';
import '../../../services/studio_file_service.dart';
import '../../../viewmodels/sheet_metal_studio_viewmodel.dart';
import 'dds_paper_canvas.dart';
import 'dds_template_library_dialog.dart';
import 'dds_ribbon_and_menu.dart';
import 'dds_cms_parameter_inspector.dart';

class DdsWorkspaceScreen extends StatefulWidget {
  final DdsDocument? initialDocument;
  final VoidCallback? onExit;
  final void Function(DsfDocument dsfDocument)? onOpenInEditor;
  final SheetMetalStudioViewModel? linkedViewModel;
  final bool isLightTheme;
  final bool isWindowMode;
  final bool isMaximized;
  final VoidCallback? onToggleWindowMode;
  final VoidCallback? onToggleMaximize;
  final VoidCallback? onDockSplit;
  final VoidCallback? onMinimize;
  final GestureDragStartCallback? onWindowDragStart;
  final GestureDragUpdateCallback? onWindowDragUpdate;
  final void Function(DdsDocument updatedDocument)? onDocumentChanged;

  const DdsWorkspaceScreen({
    super.key,
    this.initialDocument,
    this.onExit,
    this.onOpenInEditor,
    this.linkedViewModel,
    this.isLightTheme = true,
    this.isWindowMode = false,
    this.isMaximized = true,
    this.onToggleWindowMode,
    this.onToggleMaximize,
    this.onDockSplit,
    this.onMinimize,
    this.onWindowDragStart,
    this.onWindowDragUpdate,
    this.onDocumentChanged,
  });

  @override
  State<DdsWorkspaceScreen> createState() => _DdsWorkspaceScreenState();
}

class _DdsWorkspaceScreenState extends State<DdsWorkspaceScreen> with SingleTickerProviderStateMixin {
  late DdsDocument _document;
  int _activeSheetIndex = 0;
  bool _isRightPanelOpen = true;
  int _inspectorTabIndex = 0; // 0: Document Control, 1: Entities, 2: Order Traceability, 3: Parameters

  // Active markup authoring tool
  DdsMarkupTool _activeMarkupTool = DdsMarkupTool.select;
  String? _selectedAnnotationId;

  // Cache of evaluated instances: instanceId -> EvaluatedDdsInstance
  final Map<String, EvaluatedDdsInstance> _evaluatedCache = {};
  bool _isEvaluating = false;

  // Consolidated CMS Parameter Inspector (Floating Window)
  bool _isCmsFloatingInspectorOpen = false;
  Offset _cmsFloatingInspectorPos = const Offset(260, 60);
  Offset? _cmsInspectorDragOffset;

  // 3D Dimension Annotation visibility flags for presentation model
  bool _showDimWidth = true;
  bool _showDimHeight = true;
  bool _showDimPorts = true;
  bool _showDimSlots = true;
  bool _showDimFlange = true;
  bool _showDimGauge = true;

  void _handleToggleDimension(String dim) {
    setState(() {
      switch (dim) {
        case 'W': _showDimWidth = !_showDimWidth; break;
        case 'H': _showDimHeight = !_showDimHeight; break;
        case 'Ports': _showDimPorts = !_showDimPorts; break;
        case 'Slots': _showDimSlots = !_showDimSlots; break;
        case 'Flange': _showDimFlange = !_showDimFlange; break;
        case 'Gauge': _showDimGauge = !_showDimGauge; break;
      }
    });
  }

  void _handleToggleAllDimensions() {
    final allOn = _showDimWidth && _showDimHeight && _showDimPorts && _showDimSlots && _showDimFlange && _showDimGauge;
    setState(() {
      _showDimWidth = !allOn;
      _showDimHeight = !allOn;
      _showDimPorts = !allOn;
      _showDimSlots = !allOn;
      _showDimFlange = !allOn;
      _showDimGauge = !allOn;
    });
  }

  Future<void> _handleExportPdf() async {
    final defaultFileName = '${_document.projectInfo.documentNumber}_Submittal.dds';
    final jsonStr = const JsonEncoder.withIndent('  ').convert(_document.toJson());

    final path = await StudioFileService.saveFileAs(
      fileName: defaultFileName,
      content: jsonStr,
      dialogTitle: 'Export Technical Submittal Package (${_document.projectInfo.documentNumber})',
    );

    if (path != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ Client Submittal package saved: $path'),
          backgroundColor: const Color(0xFF10B981),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _document = widget.initialDocument ?? _createDefaultDocument();
    widget.linkedViewModel?.addListener(_onLinkedViewModelChanged);
    _evaluateActiveSheet();
  }

  @override
  void didUpdateWidget(covariant DdsWorkspaceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialDocument != null && widget.initialDocument != oldWidget.initialDocument) {
      if (widget.initialDocument != _document) {
        _document = widget.initialDocument!;
        if (_activeSheetIndex >= _document.sheets.length) {
          _activeSheetIndex = math.max(0, _document.sheets.length - 1);
        }
        _evaluateActiveSheet();
      }
    }
  }

  @override
  void dispose() {
    widget.linkedViewModel?.removeListener(_onLinkedViewModelChanged);
    super.dispose();
  }

  void _onLinkedViewModelChanged() {
    if (!mounted) return;
    // When main CAD document updates, trigger refresh if needed
    setState(() {});
  }

  void _handleEditInMainCad() {
    final inst = _currentProductInstance;
    if (inst == null) return;
    final eval = _evaluatedCache[inst.instanceId];
    final docToOpen = eval?.scaledBaseDocument;
    if (docToOpen != null) {
      widget.linkedViewModel?.loadDocument(docToOpen);
      widget.onOpenInEditor?.call(docToOpen);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Loaded ${inst.productName} into TruFold Main CAD window.'),
          backgroundColor: const Color(0xFF0284C7),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _handleSyncFromCad() {
    final cadDoc = widget.linkedViewModel?.document;
    if (cadDoc == null) return;

    final ref = DdsTemplateResolver.matchByDescription('${cadDoc.productType} ${cadDoc.itemName}') ??
        DdsTemplateResolver.createReference('trunking_reducer');

    final orderNum = _document.projectInfo.orderInfo?.orderNumber;
    final poNumber = (orderNum != null && orderNum.isNotEmpty) ? orderNum : 'PO-CAD-SYNC';

    final instance = DdsProductInstance(
      instanceId: 'inst_cad_${DateTime.now().millisecondsSinceEpoch}',
      productName: cadDoc.itemName.isNotEmpty ? cadDoc.itemName : 'CAD Synchronized Part',
      productCode: cadDoc.metadata['productCode'] as String? ?? 'CAD-SYNC',
      orderLine: DdsOrderLine(
        orderNumber: poNumber,
        lineNumber: (_document.productInstances.length + 1).toString().padLeft(3, '0'),
        customerItemReference: cadDoc.itemName,
        quantity: 1,
        customerDescription: 'Synchronized live from TruFold CAD Workspace',
      ),
      templateReference: ref,
      instanceParameters: {
        'port1_width': 100.0,
        'port1_height': 100.0,
      },
      coverConfiguration: const DdsCoverConfig(included: true),
    );

    final updatedDoc = _document.addProductInstance(instance, sheetTitle: instance.productName);
    setState(() {
      _document = updatedDoc;
      _activeSheetIndex = updatedDoc.sheets.length - 1;
    });
    widget.onDocumentChanged?.call(updatedDoc);
    _evaluateActiveSheet();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Imported "${instance.productName}" from CAD into TDS sheet ${_activeSheetIndex + 1}.'),
        backgroundColor: const Color(0xFF10B981),
      ),
    );
  }

  DdsDocument _createDefaultDocument() {
    final doc = DdsDocument.create(
      documentTitle: 'Hospital Cable Management System',
      documentNumber: 'TDS-2026-001',
      projectName: 'Main Hospital Building - Level 3 Services',
      client: 'Apex Health Infrastructure Group',
      consultant: 'Arup Engineering Consultants',
      contractor: 'Drake & Scull Engineering',
      preparedBy: 'Amir Khan',
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
    widget.onDocumentChanged?.call(updatedDoc);

    if (triggerEvaluation) {
      _evaluatedCache.remove(updatedInstance.instanceId);
      _evaluateInstance(updatedInstance);
    }
  }

  void _handleDeleteSheetAt(int index) {
    if (_document.sheets.length <= 1) return;
    final targetSheet = _document.sheets[index];
    final updatedSheets = List<DdsSheet>.from(_document.sheets)..removeAt(index);

    var updatedInstances = _document.productInstances;
    if (targetSheet.productInstanceId != null) {
      updatedInstances = updatedInstances.where((i) => i.instanceId != targetSheet.productInstanceId).toList();
      _evaluatedCache.remove(targetSheet.productInstanceId);
    }

    // Renumber remaining sheets sequentially
    final renumberedSheets = <DdsSheet>[];
    for (int i = 0; i < updatedSheets.length; i++) {
      renumberedSheets.add(updatedSheets[i].copyWith(sheetNumber: i + 1));
    }

    var updatedDoc = _document.copyWith(
      sheets: renumberedSheets,
      productInstances: updatedInstances,
    );
    updatedDoc = updatedDoc.updateToc();

    setState(() {
      _document = updatedDoc;
      if (_activeSheetIndex >= updatedDoc.sheets.length) {
        _activeSheetIndex = updatedDoc.sheets.length - 1;
      }
    });

    _evaluateActiveSheet();
    widget.onDocumentChanged?.call(updatedDoc);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✓ Deleted sheet "${targetSheet.title}".'),
        backgroundColor: const Color(0xFFEF4444),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _updateSelectedAnnotation(DdsAnnotation Function(DdsAnnotation current) updater) {
    if (_selectedAnnotationId == null) return;
    final currentList = _currentSheet.annotations;
    final idx = currentList.indexWhere((a) => a.id == _selectedAnnotationId);
    if (idx == -1) return;
    final updatedAnn = updater(currentList[idx]);
    final updatedList = List<DdsAnnotation>.from(currentList)..[idx] = updatedAnn;
    _handleAnnotationsChanged(updatedList);
  }

  void _deleteSelectedAnnotation({String? id}) {
    final targetId = id ?? _selectedAnnotationId;
    if (targetId == null) return;
    final list = _currentSheet.annotations.where((a) => a.id != targetId).toList();
    _handleAnnotationsChanged(list);
    if (_selectedAnnotationId == targetId) {
      setState(() => _selectedAnnotationId = null);
    }
  }

  void _nudgeSelectedAnnotation(double dx, double dy) {
    _updateSelectedAnnotation((ann) {
      if (ann is DdsNoteBoxAnnotation) {
        return ann.copyWith(x: (ann.x + dx).clamp(0.0, 270.0), y: (ann.y + dy).clamp(0.0, 190.0));
      } else if (ann is DdsApprovalStampAnnotation) {
        return ann.copyWith(x: (ann.x + dx).clamp(0.0, 250.0), y: (ann.y + dy).clamp(0.0, 180.0));
      } else if (ann is DdsLeaderNoteAnnotation) {
        return ann.copyWith(
          targetPoint: CadPoint2D(ann.targetPoint.x + dx, ann.targetPoint.y + dy),
          textPosition: CadPoint2D(ann.textPosition.x + dx, ann.textPosition.y + dy),
        );
      } else if (ann is DdsLinearDimensionAnnotation) {
        return ann.copyWith(
          p1: CadPoint2D(ann.p1.x + dx, ann.p1.y + dy),
          p2: CadPoint2D(ann.p2.x + dx, ann.p2.y + dy),
        );
      } else if (ann is DdsRevisionCloudAnnotation) {
        return ann.copyWith(
          points: ann.points.map((p) => CadPoint2D(p.x + dx, p.y + dy)).toList(),
        );
      }
      return ann;
    });
  }

  // ===========================================================================
  // Drawing Component vs Text Copy / Paste Handlers
  // ===========================================================================

  bool _isEditingText() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return false;
    final ctx = focus.context;
    if (ctx == null || !ctx.mounted) return false;
    if (ctx.widget is EditableText) return true;
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  void _handleCopy() {
    if (_isEditingText()) {
      final focus = FocusManager.instance.primaryFocus;
      if (focus?.context != null && focus!.context!.mounted) {
        Actions.maybeInvoke(focus.context!, CopySelectionTextIntent.copy);
      }
      return;
    }

    if (_selectedAnnotationId != null) {
      final ann = _currentSheet.annotations.cast<DdsAnnotation?>().firstWhere(
        (a) => a?.id == _selectedAnnotationId,
        orElse: () => null,
      );
      if (ann != null) {
        StudioClipboardService.copyAnnotation(ann);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Copied ${ann.type.name} to drawing component clipboard.'),
            backgroundColor: const Color(0xFF0284C7),
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No drawing component or annotation selected to copy.'),
        backgroundColor: Color(0xFF64748B),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _handlePaste() {
    if (_isEditingText()) {
      final focus = FocusManager.instance.primaryFocus;
      if (focus?.context != null && focus!.context!.mounted) {
        Actions.maybeInvoke(focus.context!, const PasteTextIntent(SelectionChangedCause.keyboard));
      }
      return;
    }

    if (StudioClipboardService.hasAnnotationContent) {
      final newAnn = StudioClipboardService.pasteAnnotationIntoSheet(_currentSheet, offsetX: 12.0, offsetY: 12.0);
      if (newAnn != null) {
        final updatedList = [..._currentSheet.annotations, newAnn];
        _handleAnnotationsChanged(updatedList);
        setState(() {
          _selectedAnnotationId = newAnn.id;
          _inspectorTabIndex = 1;
          _isRightPanelOpen = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pasted ${newAnn.type.name} onto sheet ${_currentSheet.sheetNumber}.'),
            backgroundColor: const Color(0xFF059669),
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }
    } else if (StudioClipboardService.hasCadContent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('CAD primitive in clipboard. Switch to 2D CAD canvas to paste CAD features.'),
          backgroundColor: Color(0xFFD97706),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Drawing component clipboard is empty.'),
        backgroundColor: Color(0xFF64748B),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _handleSelectAll() {
    if (_isEditingText()) {
      final focus = FocusManager.instance.primaryFocus;
      if (focus?.context != null && focus!.context!.mounted) {
        Actions.maybeInvoke(focus.context!, const SelectAllTextIntent(SelectionChangedCause.keyboard));
      }
    }
  }

  void _handleDelete() {
    if (_isEditingText()) {
      return;
    }
    if (_selectedAnnotationId != null) {
      _deleteSelectedAnnotation(id: _selectedAnnotationId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Deleted selected drawing component.'),
          backgroundColor: Color(0xFFDC2626),
          duration: Duration(seconds: 1),
        ),
      );
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
      widget.onDocumentChanged?.call(importResult.document);

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
      widget.onDocumentChanged?.call(openedDoc);

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
            _inspectorTabIndex = 3; // Go to Parameter Editor (Tab 3)
            _isRightPanelOpen = true;
          }
        });
        widget.onDocumentChanged?.call(updatedDoc);
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

    final updatedDoc = _document.copyWith(sheets: updatedSheets);
    setState(() {
      _document = updatedDoc;
    });
    widget.onDocumentChanged?.call(updatedDoc);
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
    final isLight = widget.isLightTheme;
    final scaffoldBg = isLight ? const Color(0xFFF1F5F9) : const Color(0xFF0B132B);
    final deskBg = isLight ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A);
    final dividerCol = isLight ? const Color(0xFFCBD5E1) : const Color(0xFF1E293B);

    return Scaffold(
      backgroundColor: scaffoldBg,
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyC, control: true): _handleCopy,
          const SingleActivator(LogicalKeyboardKey.keyC, meta: true): _handleCopy,
          const SingleActivator(LogicalKeyboardKey.keyV, control: true): _handlePaste,
          const SingleActivator(LogicalKeyboardKey.keyV, meta: true): _handlePaste,
          const SingleActivator(LogicalKeyboardKey.keyA, control: true): _handleSelectAll,
          const SingleActivator(LogicalKeyboardKey.keyA, meta: true): _handleSelectAll,
          const SingleActivator(LogicalKeyboardKey.delete): _handleDelete,
          const SingleActivator(LogicalKeyboardKey.backspace): _handleDelete,
        },
        child: SafeArea(
        child: Column(
          children: [
            // 1. Dedicated Window Title Bar (with Minimize, Maximize/Restore, Close, and drag handling)
            DdsWindowTitleBar(
              document: _document,
              isMaximized: widget.isMaximized,
              isWindowMode: widget.isWindowMode,
              onMinimize: widget.onMinimize,
              onToggleMaximize: widget.onToggleMaximize,
              onDockSplit: widget.onDockSplit,
              onClose: widget.onExit,
              onDragStart: widget.onWindowDragStart,
              onDragUpdate: widget.onWindowDragUpdate,
            ),

            // 2. Dedicated TDS Menu Bar (File, Edit, Library, Document, Order, View, CAD Link)
            DdsMenuBarWidget(
              document: _document,
              onNewDocument: () {
                final def = _createDefaultDocument();
                setState(() {
                  _document = def;
                  _activeSheetIndex = 0;
                });
                widget.onDocumentChanged?.call(def);
                _evaluateActiveSheet();
              },
              onOpenDocument: _handleOpenDds,
              onSaveDocument: _handleSaveDds,
              onSaveAsDocument: _handleSaveDds,
              onExportPdf: _handleExportPdf,
              onImportExcel: _handleImportExcel,
              onAddProductSheet: () {
                final newInstance = DdsProductInstance(
                  instanceId: 'inst_${DateTime.now().millisecondsSinceEpoch}',
                  productName: 'Parametric Cable Trunking Fitting',
                  productCode: 'CMS-TRK-FITTING',
                  orderLine: DdsOrderLine(
                    orderNumber: _document.projectInfo.orderInfo?.orderNumber ?? 'PO-88210',
                    lineNumber: (_document.productInstances.length + 1).toString().padLeft(3, '0'),
                    customerItemReference: 'ITEM-${_document.productInstances.length + 1}',
                    quantity: 1,
                    customerDescription: 'HVAC Sheet Metal CMS Fitting',
                  ),
                  templateReference: DdsTemplateResolver.createReference('trunking_reducer'),
                  instanceParameters: {
                    'port1_width': 150.0,
                    'port1_height': 100.0,
                    'port2_width': 75.0,
                    'port2_height': 50.0,
                    'coupler_slot_length': 20.0,
                    'coupler_slot_width': 9.0,
                    'coupler_slot_pitch': 25.0,
                    'flange_direction': 0.0,
                    'base_flange_size': 20.0,
                    'cover_flange_size': 15.0,
                    'thickness': 1.5,
                  },
                );
                final updated = _document.addProductInstance(newInstance, sheetTitle: newInstance.productName);
                setState(() {
                  _document = updated;
                  _activeSheetIndex = updated.sheets.length - 1;
                });
                widget.onDocumentChanged?.call(updated);
                _evaluateActiveSheet();
              },
              onAddCoverSheet: () {
                final newSheet = DdsSheet(
                  sheetId: 'sheet_cover_${DateTime.now().millisecondsSinceEpoch}',
                  sheetNumber: _document.sheets.length + 1,
                  title: 'PROJECT COVER & SCHEDULE OF FITTINGS',
                  sheetType: DdsSheetType.coverSchedule,
                );
                final updated = _document.copyWith(sheets: [..._document.sheets, newSheet]);
                setState(() {
                  _document = updated;
                  _activeSheetIndex = updated.sheets.length - 1;
                });
                widget.onDocumentChanged?.call(updated);
              },
              onDuplicateSheet: () {
                final current = _currentSheet;
                final duplicated = current.copyWith(
                  sheetId: 'sheet_dup_${DateTime.now().millisecondsSinceEpoch}',
                  sheetNumber: _document.sheets.length + 1,
                  title: '${current.title} (Copy)',
                );
                final updated = _document.copyWith(sheets: [..._document.sheets, duplicated]);
                setState(() {
                  _document = updated;
                  _activeSheetIndex = updated.sheets.length - 1;
                });
                widget.onDocumentChanged?.call(updated);
              },
              onDeleteSheet: _document.sheets.length > 1 ? () => _handleDeleteSheetAt(_activeSheetIndex) : null,
              onOpenLibrary: _handleOpenTemplateLibrary,
              onEditInMainCad: _handleEditInMainCad,
              onSyncFromCad: _handleSyncFromCad,
              onToggleProperties: () => setState(() => _isRightPanelOpen = !_isRightPanelOpen),
              onToggleCmsInspector: () => setState(() {
                _isRightPanelOpen = true;
                _inspectorTabIndex = 3;
              }),
              onClose: widget.onExit,
            ),

            // 3. Dedicated TDS Ribbon Toolbar (Grouped controls)
            DdsRibbonToolbarWidget(
              document: _document,
              activeInstance: _currentProductInstance,
              evaluatedInstance: _currentProductInstance != null ? _evaluatedCache[_currentProductInstance!.instanceId] : null,
              onNewDoc: () {
                final def = _createDefaultDocument();
                setState(() {
                  _document = def;
                  _activeSheetIndex = 0;
                });
                widget.onDocumentChanged?.call(def);
                _evaluateActiveSheet();
              },
              onOpenDoc: _handleOpenDds,
              onSaveDoc: _handleSaveDds,
              onExportPdf: _handleExportPdf,
              onOpenLibrary: _handleOpenTemplateLibrary,
              onImportExcel: _handleImportExcel,
              onAddSheet: () {
                final newInstance = DdsProductInstance(
                  instanceId: 'inst_${DateTime.now().millisecondsSinceEpoch}',
                  productName: 'Parametric Cable Trunking Fitting',
                  productCode: 'CMS-TRK-FITTING',
                  orderLine: DdsOrderLine(
                    orderNumber: _document.projectInfo.orderInfo?.orderNumber ?? 'PO-88210',
                    lineNumber: (_document.productInstances.length + 1).toString().padLeft(3, '0'),
                    customerItemReference: 'ITEM-${_document.productInstances.length + 1}',
                    quantity: 1,
                    customerDescription: 'HVAC Sheet Metal CMS Fitting',
                  ),
                  templateReference: DdsTemplateResolver.createReference('trunking_reducer'),
                  instanceParameters: {
                    'port1_width': 150.0,
                    'port1_height': 100.0,
                    'port2_width': 75.0,
                    'port2_height': 50.0,
                    'coupler_slot_length': 20.0,
                    'coupler_slot_width': 9.0,
                    'coupler_slot_pitch': 25.0,
                    'flange_direction': 0.0,
                    'base_flange_size': 20.0,
                    'cover_flange_size': 15.0,
                    'thickness': 1.5,
                  },
                );
                final updated = _document.addProductInstance(newInstance, sheetTitle: newInstance.productName);
                setState(() {
                  _document = updated;
                  _activeSheetIndex = updated.sheets.length - 1;
                });
                widget.onDocumentChanged?.call(updated);
                _evaluateActiveSheet();
              },
              onEditInMainCad: _handleEditInMainCad,
              onSyncFromCad: _handleSyncFromCad,
              onToggleProperties: () => setState(() => _isRightPanelOpen = !_isRightPanelOpen),
              onToggleCmsInspector: () => setState(() {
                _isRightPanelOpen = true;
                _inspectorTabIndex = 3;
              }),
              isPropertiesOpen: _isRightPanelOpen,
              isCmsInspectorOpen: _isRightPanelOpen && _inspectorTabIndex == 3,
              showDimWidth: _showDimWidth,
              showDimHeight: _showDimHeight,
              showDimPorts: _showDimPorts,
              showDimSlots: _showDimSlots,
              showDimFlange: _showDimFlange,
              showDimGauge: _showDimGauge,
              onToggleDimension: _handleToggleDimension,
              onToggleAllDimensions: _handleToggleAllDimensions,
            ),

            // Main Workspace Layout: Navigator | Paper Canvas | Inspector
            Expanded(
              child: Row(
                children: [
                  // Left: Sheet & Product Index Navigator (280px)
                  _buildLeftSheetNavigator(),
                  VerticalDivider(width: 1, color: dividerCol),

                  // Center: Paper Layout Canvas
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Container(
                            color: deskBg,
                            padding: const EdgeInsets.all(24.0),
                            child: DdsPaperCanvas(
                              document: _document,
                              sheet: _currentSheet,
                              evaluatedInstance: _currentProductInstance != null
                                  ? _evaluatedCache[_currentProductInstance!.instanceId]
                                  : null,
                              viewModel: widget.linkedViewModel,
                              activeMarkupTool: _activeMarkupTool,
                              selectedAnnotationId: _selectedAnnotationId,
                              showDimWidth: _showDimWidth,
                              showDimHeight: _showDimHeight,
                              showDimPorts: _showDimPorts,
                              showDimSlots: _showDimSlots,
                              showDimFlange: _showDimFlange,
                              showDimThickness: _showDimGauge,
                              onDimensionToggled: (dim, visible) {
                                setState(() {
                                  switch (dim) {
                                    case 'W': _showDimWidth = visible; break;
                                    case 'H': _showDimHeight = visible; break;
                                    case 'Ports': _showDimPorts = visible; break;
                                    case 'Slots': _showDimSlots = visible; break;
                                    case 'Flange': _showDimFlange = visible; break;
                                    case 'Gauge': _showDimGauge = visible; break;
                                  }
                                });
                              },
                              onAnnotationsChanged: _handleAnnotationsChanged,
                              onAnnotationSelected: (id) => setState(() {
                                _selectedAnnotationId = id;
                                if (id != null) {
                                  _inspectorTabIndex = 1;
                                  _isRightPanelOpen = true;
                                }
                              }),
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
                              onDeleteSheet: _document.sheets.length > 1
                                  ? () => _handleDeleteSheetAt(_activeSheetIndex)
                                  : null,
                              onViewSettingsChanged: (updatedSettings) {
                                final current = _currentSheet;
                                if (current.viewSettings == updatedSettings) return;
                                final updated = current.copyWith(viewSettings: updatedSettings);
                                final updatedSheets = _document.sheets.map((s) => s.sheetId == updated.sheetId ? updated : s).toList();
                                final updatedDoc = _document.copyWith(sheets: updatedSheets);
                                void apply() {
                                  if (!mounted) return;
                                  setState(() {
                                    _document = updatedDoc;
                                  });
                                  widget.onDocumentChanged?.call(updatedDoc);
                                }

                                if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
                                  WidgetsBinding.instance.addPostFrameCallback((_) => apply());
                                } else {
                                  apply();
                                }
                              },
                              onProjectInfoChanged: (newProj) {
                                final updatedDoc = _document.copyWith(projectInfo: newProj);
                                void apply() {
                                  if (!mounted) return;
                                  setState(() {
                                    _document = updatedDoc;
                                  });
                                  widget.onDocumentChanged?.call(updatedDoc);
                                }

                                if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
                                  WidgetsBinding.instance.addPostFrameCallback((_) => apply());
                                } else {
                                  apply();
                                }
                              },
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
                                color: isLight ? Colors.white : const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(6.0),
                                border: Border.all(color: const Color(0xFF38BDF8)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    blurRadius: 8,
                                  ),
                                ],
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
                                    style: TextStyle(color: Color(0xFF0284C7), fontSize: 11.0, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // Floating Consolidated CMS Parameter Inspector (F6)
                        if (_isCmsFloatingInspectorOpen && _currentProductInstance != null)
                          Positioned(
                            left: _cmsFloatingInspectorPos.dx,
                            top: _cmsFloatingInspectorPos.dy,
                            child: DdsCmsParameterInspector(
                              instance: _currentProductInstance,
                              onInstanceChanged: (updatedInst) {
                                _updateInstanceInDocument(updatedInst);
                              },
                              isLightTheme: widget.isLightTheme,
                              isDetached: true,
                              onClose: () => setState(() => _isCmsFloatingInspectorOpen = false),
                              onDetach: () {
                                setState(() {
                                  _isCmsFloatingInspectorOpen = false;
                                  _isRightPanelOpen = true;
                                  _inspectorTabIndex = 3;
                                });
                              },
                              onDragStart: (details) {
                                _cmsInspectorDragOffset = details.globalPosition - _cmsFloatingInspectorPos;
                              },
                              onDragUpdate: (details) {
                                if (_cmsInspectorDragOffset != null) {
                                  setState(() {
                                    _cmsFloatingInspectorPos = details.globalPosition - _cmsInspectorDragOffset!;
                                  });
                                }
                              },
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Right: Inspector / Parameter Editor (340px)
                  if (_isRightPanelOpen) ...[
                    VerticalDivider(width: 1, color: dividerCol),
                    SizedBox(
                      width: 340,
                      child: _buildRightInspectorPanel(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  // ===========================================================================
  // Left Sheet Navigator
  // ===========================================================================

  Widget _buildLeftSheetNavigator() {
    final isLight = widget.isLightTheme;
    final navBg = isLight ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    final headerBg = isLight ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B);
    final divCol = isLight ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B);

    return Container(
      width: 280,
      color: navBg,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
            color: headerBg,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'SHEET NAVIGATOR',
                  style: TextStyle(
                    color: isLight ? const Color(0xFF475569) : const Color(0xFF94A3B8),
                    fontSize: 11.0,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
                Text(
                  '${_document.totalSheets} Sheets',
                  style: const TextStyle(color: Color(0xFF0284C7), fontSize: 11.0, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: divCol),

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
          Divider(height: 1, color: divCol),

          // Sheet List
          Expanded(
            child: ListView.separated(
              itemCount: _document.sheets.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: divCol),
              itemBuilder: (context, idx) {
                final sheet = _document.sheets[idx];
                final isSelected = idx == _activeSheetIndex;
                final inst = _document.findInstance(sheet.productInstanceId);

                return ListTile(
                  dense: true,
                  selected: isSelected,
                  selectedTileColor: isLight
                      ? const Color(0xFFE0F2FE)
                      : const Color(0xFF0284C7).withValues(alpha: 0.2),
                  leading: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF0284C7)
                          : (isLight ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B)),
                      borderRadius: BorderRadius.circular(4.0),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      sheet.sheetNumber.toString().padLeft(2, '0'),
                      style: TextStyle(
                        color: isSelected ? Colors.white : (isLight ? const Color(0xFF475569) : const Color(0xFF94A3B8)),
                        fontSize: 11.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    sheet.isCoverPage ? 'Transmittal & Schedule' : (inst?.productName ?? sheet.title),
                    style: TextStyle(
                      color: isSelected
                          ? (isLight ? const Color(0xFF0369A1) : Colors.white)
                          : (isLight ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1)),
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
                      color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                      fontSize: 10.0,
                    ),
                  ),
                  trailing: _document.sheets.length > 1
                      ? IconButton(
                          icon: const Icon(Icons.delete_outline, size: 16),
                          color: const Color(0xFFEF4444),
                          tooltip: 'Delete Sheet',
                          onPressed: () => _handleDeleteSheetAt(idx),
                        )
                      : null,
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
    final isLight = widget.isLightTheme;
    final panelBg = isLight ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    final headerBg = isLight ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B);
    final divCol = isLight ? const Color(0xFFE2E8F0) : const Color(0xFF334155);

    return Container(
      color: panelBg,
      child: Column(
        children: [
          // Inspector Tab Bar (4 Tabs: Doc Control, Entities, Traceability, Parameters)
          Container(
            color: headerBg,
            child: Row(
              children: [
                _buildInspectorTab(0, 'Doc Control', Icons.badge_outlined),
                _buildInspectorTab(1, 'Entities', Icons.layers_outlined),
                _buildInspectorTab(2, 'Traceability', Icons.hub_outlined),
                _buildInspectorTab(3, 'Parameters', Icons.tune_outlined),
              ],
            ),
          ),
          Divider(height: 1, color: divCol),

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
    final isLight = widget.isLightTheme;

    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _inspectorTabIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10.0),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? const Color(0xFF0284C7) : Colors.transparent,
                width: 2.0,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected
                    ? const Color(0xFF0284C7)
                    : (isLight ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
              ),
              const SizedBox(width: 4.0),
              Text(
                title,
                style: TextStyle(
                  color: isSelected
                    ? (isLight ? const Color(0xFF0284C7) : Colors.white)
                    : (isLight ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
                  fontSize: 10.5,
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
        return _buildDocumentControlForm();
      case 1:
        return _buildEntitiesInspectorTab();
      case 2:
        return _buildOrderTraceabilityView(instance);
      case 3:
        return _buildParametersInspectorTab(instance);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildParametersInspectorTab(DdsProductInstance? instance) {
    if (instance == null) {
      final isLight = widget.isLightTheme;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tune_outlined, size: 36, color: isLight ? Colors.grey[400] : Colors.grey[600]),
              const SizedBox(height: 12),
              Text(
                'No Product Selected',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isLight ? Colors.grey[700] : Colors.grey[300],
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Select an item from the Bill of Materials or BOM Schedule to inspect and modify live CMS parameters.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: isLight ? Colors.grey[600] : Colors.grey[400],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return DdsCmsParameterInspector(
      instance: instance,
      onInstanceChanged: (updatedInst) {
        _updateInstanceInDocument(updatedInst);
      },
      isLightTheme: widget.isLightTheme,
      isDetached: false,
      onDetach: () {
        setState(() {
          _isCmsFloatingInspectorOpen = true;
        });
      },
    );
  }

  Widget _buildEntitiesInspectorTab() {
    final isLight = widget.isLightTheme;
    final annotations = _currentSheet.annotations;
    final selectedAnn = _selectedAnnotationId != null
        ? annotations.cast<DdsAnnotation?>().firstWhere((a) => a?.id == _selectedAnnotationId, orElse: () => null)
        : null;

    final subHeadingStyle = TextStyle(
      fontSize: 10.0,
      fontWeight: FontWeight.bold,
      color: isLight ? const Color(0xFF475569) : const Color(0xFF94A3B8),
      letterSpacing: 0.5,
    );

    return ListView(
      padding: const EdgeInsets.all(12.0),
      children: [
        // Section Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('ENTITIES ON SHEET (${annotations.length})', style: subHeadingStyle),
            if (annotations.isNotEmpty)
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.clear_all, size: 13, color: Color(0xFFEF4444)),
                label: const Text('Clear All', style: TextStyle(fontSize: 10.0, color: Color(0xFFEF4444))),
                onPressed: () {
                  _handleAnnotationsChanged([]);
                  setState(() => _selectedAnnotationId = null);
                },
              ),
          ],
        ),
        const SizedBox(height: 8.0),

        if (annotations.isEmpty)
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: isLight ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(6.0),
              border: Border.all(color: isLight ? const Color(0xFFE2E8F0) : const Color(0xFF334155)),
            ),
            child: Column(
              children: [
                Icon(Icons.layers_clear_outlined, size: 28, color: isLight ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                const SizedBox(height: 8.0),
                Text(
                  'No drawn entities on Sheet ${_activeSheetIndex + 1}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: isLight ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                  ),
                ),
                const SizedBox(height: 4.0),
                Text(
                  'Use the markup palette above to add Note Boxes, Leader Notes, Review Stamps, Clouds, or Dimensions.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10.0, color: isLight ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 10.0),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                  ),
                  icon: const Icon(Icons.note_alt_outlined, size: 14, color: Colors.white),
                  label: const Text('+ Add Note Box', style: TextStyle(fontSize: 11, color: Colors.white)),
                  onPressed: () {
                    final newNote = DdsNoteBoxAnnotation(
                      id: 'notebox_${DateTime.now().millisecondsSinceEpoch}',
                      x: 60.0,
                      y: 40.0,
                      width: 110.0,
                      height: 35.0,
                      text: 'New Specification Note',
                      fontSize: 9.0,
                    );
                    _handleAnnotationsChanged([..._currentSheet.annotations, newNote]);
                    setState(() => _selectedAnnotationId = newNote.id);
                  },
                ),
              ],
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: isLight ? Colors.white : const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(6.0),
              border: Border.all(color: isLight ? const Color(0xFFE2E8F0) : const Color(0xFF334155)),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: annotations.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: isLight ? const Color(0xFFF1F5F9) : const Color(0xFF334155)),
              itemBuilder: (context, i) {
                final ann = annotations[i];
                final isSel = ann.id == _selectedAnnotationId;

                IconData icon;
                Color iconColor;
                String title;
                String subtitle;

                if (ann is DdsNoteBoxAnnotation) {
                  icon = Icons.sticky_note_2_outlined;
                  iconColor = const Color(0xFFF59E0B);
                  title = ann.text.isNotEmpty ? ann.text : 'Note Box';
                  subtitle = 'Pos: (${ann.x.toStringAsFixed(0)}, ${ann.y.toStringAsFixed(0)}) mm • ${ann.fontSize.toStringAsFixed(0)}pt';
                } else if (ann is DdsLeaderNoteAnnotation) {
                  icon = Icons.call_made;
                  iconColor = const Color(0xFF0284C7);
                  title = ann.text.isNotEmpty ? ann.text : 'Leader Callout';
                  subtitle = 'Target: (${ann.targetPoint.x.toStringAsFixed(0)}, ${ann.targetPoint.y.toStringAsFixed(0)}) mm';
                } else if (ann is DdsApprovalStampAnnotation) {
                  icon = Icons.verified_outlined;
                  iconColor = const Color(0xFF10B981);
                  title = ann.status;
                  subtitle = 'Pos: (${ann.x.toStringAsFixed(0)}, ${ann.y.toStringAsFixed(0)}) mm • ${ann.reviewedBy.isNotEmpty ? ann.reviewedBy : "Reviewer"}';
                } else if (ann is DdsRevisionCloudAnnotation) {
                  icon = Icons.cloud_outlined;
                  iconColor = const Color(0xFFA855F7);
                  title = 'Revision Cloud: ${ann.revisionTag}';
                  subtitle = '${ann.points.length} vertices • r: ${ann.arcRadius}mm';
                } else if (ann is DdsLinearDimensionAnnotation) {
                  icon = Icons.straighten;
                  iconColor = const Color(0xFF00E5FF);
                  title = ann.displayText;
                  subtitle = 'Offset: ${ann.offsetDistance.toStringAsFixed(0)}mm';
                } else {
                  icon = Icons.layers_outlined;
                  iconColor = Colors.grey;
                  title = ann.type.name;
                  subtitle = 'Annotation';
                }

                return InkWell(
                  onTap: () => setState(() => _selectedAnnotationId = ann.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 7.0),
                    decoration: BoxDecoration(
                      color: isSel ? const Color(0xFF0284C7).withValues(alpha: isLight ? 0.12 : 0.25) : Colors.transparent,
                      border: isSel
                          ? const Border(left: BorderSide(color: Color(0xFF0284C7), width: 3.0))
                          : null,
                    ),
                    child: Row(
                      children: [
                        Icon(icon, size: 16, color: iconColor),
                        const SizedBox(width: 8.0),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title,
                                style: TextStyle(
                                  fontSize: 11.0,
                                  fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                                  color: isSel
                                      ? const Color(0xFF0284C7)
                                      : (isLight ? const Color(0xFF1E293B) : Colors.white),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                subtitle,
                                style: TextStyle(fontSize: 9.0, color: isLight ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 15, color: Color(0xFFEF4444)),
                          tooltip: 'Delete Entity',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _deleteSelectedAnnotation(id: ann.id),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

        const SizedBox(height: 16.0),

        // Section 2: Property Inspector for Selected Entity
        if (selectedAnn != null) ...[
          Container(
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              color: isLight ? Colors.white : const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(6.0),
              border: Border.all(color: const Color(0xFF0284C7), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0284C7).withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.tune, size: 14, color: Color(0xFF0284C7)),
                        const SizedBox(width: 6),
                        Text(
                          'PROPERTY INSPECTOR',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF0284C7),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    InkWell(
                      onTap: () => setState(() => _selectedAnnotationId = null),
                      child: const Text('Deselect', style: TextStyle(fontSize: 10.0, color: Color(0xFF64748B))),
                    ),
                  ],
                ),
                const Divider(height: 14),

                // 1. Text / Label Edit
                if (selectedAnn is DdsNoteBoxAnnotation) ...[
                  _buildPropertyLabel('NOTE TEXT CONTENT'),
                  TextFormField(
                    initialValue: selectedAnn.text,
                    key: ValueKey('text_${selectedAnn.id}'),
                    maxLines: 2,
                    style: const TextStyle(fontSize: 11),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.all(8),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (val) => _updateSelectedAnnotation((c) => (c as DdsNoteBoxAnnotation).copyWith(text: val)),
                  ),
                  const SizedBox(height: 10),
                  // Font Size & Border
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildPropertyLabel('FONT SIZE (${selectedAnn.fontSize.toInt()} PT)'),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove, size: 14),
                                  onPressed: () => _updateSelectedAnnotation((c) => (c as DdsNoteBoxAnnotation).copyWith(fontSize: (c.fontSize - 1).clamp(8.0, 28.0))),
                                ),
                                Text('${selectedAnn.fontSize.toInt()} pt', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                IconButton(
                                  icon: const Icon(Icons.add, size: 14),
                                  onPressed: () => _updateSelectedAnnotation((c) => (c as DdsNoteBoxAnnotation).copyWith(fontSize: (c.fontSize + 1).clamp(8.0, 28.0))),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildPropertyLabel('BORDER'),
                          Checkbox(
                            value: selectedAnn.hasBorder,
                            onChanged: (v) => _updateSelectedAnnotation((c) => (c as DdsNoteBoxAnnotation).copyWith(hasBorder: v ?? true)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ] else if (selectedAnn is DdsLeaderNoteAnnotation) ...[
                  _buildPropertyLabel('CALLOUT TEXT'),
                  TextFormField(
                    initialValue: selectedAnn.text,
                    key: ValueKey('text_${selectedAnn.id}'),
                    style: const TextStyle(fontSize: 11),
                    decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.all(8), border: OutlineInputBorder()),
                    onChanged: (val) => _updateSelectedAnnotation((c) => (c as DdsLeaderNoteAnnotation).copyWith(text: val)),
                  ),
                ] else if (selectedAnn is DdsApprovalStampAnnotation) ...[
                  _buildPropertyLabel('APPROVAL STATUS'),
                  DropdownButtonFormField<String>(
                    initialValue: selectedAnn.status,
                    isDense: true,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF0F172A)),
                    items: const [
                      DropdownMenuItem(value: 'A - Approved', child: Text('A - Approved')),
                      DropdownMenuItem(value: 'B - Approved as Noted', child: Text('B - Approved as Noted')),
                      DropdownMenuItem(value: 'C - Revise and Resubmit', child: Text('C - Revise & Resubmit')),
                      DropdownMenuItem(value: 'For Approval', child: Text('For Approval')),
                    ],
                    onChanged: (val) => _updateSelectedAnnotation((c) => (c as DdsApprovalStampAnnotation).copyWith(status: val ?? 'For Approval')),
                  ),
                  const SizedBox(height: 8),
                  _buildPropertyLabel('REVIEWED BY'),
                  TextFormField(
                    initialValue: selectedAnn.reviewedBy,
                    key: ValueKey('revBy_${selectedAnn.id}'),
                    style: const TextStyle(fontSize: 11),
                    decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.all(8), border: OutlineInputBorder()),
                    onChanged: (val) => _updateSelectedAnnotation((c) => (c as DdsApprovalStampAnnotation).copyWith(reviewedBy: val)),
                  ),
                ] else if (selectedAnn is DdsRevisionCloudAnnotation) ...[
                  _buildPropertyLabel('REVISION TAG'),
                  TextFormField(
                    initialValue: selectedAnn.revisionTag,
                    key: ValueKey('revTag_${selectedAnn.id}'),
                    style: const TextStyle(fontSize: 11),
                    decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.all(8), border: OutlineInputBorder()),
                    onChanged: (val) => _updateSelectedAnnotation((c) => (c as DdsRevisionCloudAnnotation).copyWith(revisionTag: val)),
                  ),
                ] else if (selectedAnn is DdsLinearDimensionAnnotation) ...[
                  _buildPropertyLabel('OVERRIDE TEXT'),
                  TextFormField(
                    initialValue: selectedAnn.textOverride ?? '',
                    key: ValueKey('dimOver_${selectedAnn.id}'),
                    style: const TextStyle(fontSize: 11),
                    decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.all(8), border: OutlineInputBorder(), hintText: 'Auto measured length'),
                    onChanged: (val) => _updateSelectedAnnotation((c) => (c as DdsLinearDimensionAnnotation).copyWith(textOverride: val)),
                  ),
                ],

                const SizedBox(height: 12),

                // 2. Position (Movable Nudge Controls)
                _buildPropertyLabel('POSITION & NUDGE (PAPER MM)'),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_left, size: 20),
                      tooltip: 'Nudge Left 5mm',
                      onPressed: () => _nudgeSelectedAnnotation(-5.0, 0.0),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_drop_up, size: 20),
                      tooltip: 'Nudge Up 5mm',
                      onPressed: () => _nudgeSelectedAnnotation(0.0, -5.0),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_drop_down, size: 20),
                      tooltip: 'Nudge Down 5mm',
                      onPressed: () => _nudgeSelectedAnnotation(0.0, 5.0),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_right, size: 20),
                      tooltip: 'Nudge Right 5mm',
                      onPressed: () => _nudgeSelectedAnnotation(5.0, 0.0),
                    ),
                  ],
                ),

                const Divider(height: 16),

                // 3. Delete Entity Action Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    icon: const Icon(Icons.delete_outline, size: 14),
                    label: const Text('Delete Entity', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    onPressed: () => _deleteSelectedAnnotation(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPropertyLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Text(
        text,
        style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Color(0xFF64748B), letterSpacing: 0.4),
      ),
    );
  }

  Widget _buildDocumentControlForm() {
    final proj = _document.projectInfo;
    final isLight = widget.isLightTheme;

    void updateProj(DdsProjectInfo newProj) {
      final updated = _document.copyWith(projectInfo: newProj);
      setState(() => _document = updated);
      widget.onDocumentChanged?.call(updated);
    }

    return ListView(
      padding: const EdgeInsets.all(14.0),
      children: [
        Text(
          'PROJECT METADATA',
          style: TextStyle(
            color: isLight ? const Color(0xFF0F172A) : Colors.white,
            fontSize: 11.0,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8.0),
        _buildTextField('Document Title', proj.documentTitle, (v) {
          updateProj(proj.copyWith(documentTitle: v));
        }),
        _buildTextField('Document Number', proj.documentNumber, (v) {
          updateProj(proj.copyWith(documentNumber: v));
        }),
        _buildTextField('Revision Index', proj.revision, (v) {
          updateProj(proj.copyWith(revision: v));
        }),
        _buildTextField('Client Name', proj.client, (v) {
          updateProj(proj.copyWith(client: v));
        }),
        _buildTextField('Project Name', proj.projectName, (v) {
          updateProj(proj.copyWith(projectName: v));
        }),
        _buildTextField('Consultant', proj.consultant, (v) {
          updateProj(proj.copyWith(consultant: v));
        }),
        _buildTextField('Contractor', proj.contractor, (v) {
          updateProj(proj.copyWith(contractor: v));
        }),

        const SizedBox(height: 16.0),
        Divider(color: isLight ? const Color(0xFFCBD5E1) : const Color(0xFF334155)),
        const SizedBox(height: 8.0),

        Text(
          'QUALITY SIGN-OFF (ISO 7200 / DIN 6771)',
          style: TextStyle(
            color: isLight ? const Color(0xFF0F172A) : Colors.white,
            fontSize: 11.0,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8.0),

        Row(
          children: [
            Expanded(
              child: _buildTextField('DESIGNED BY', proj.designedBy, (v) {
                updateProj(proj.copyWith(designedBy: v));
              }),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildDatePickerField('DATE', proj.effectiveDesignedDate, (v) {
                updateProj(proj.copyWith(designedDate: v));
              }),
            ),
          ],
        ),

        Row(
          children: [
            Expanded(
              child: _buildTextField('DRAWN BY', proj.drawnBy, (v) {
                updateProj(proj.copyWith(drawnBy: v));
              }),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildDatePickerField('DATE', proj.effectiveDrawnDate, (v) {
                updateProj(proj.copyWith(drawnDate: v));
              }),
            ),
          ],
        ),

        Row(
          children: [
            Expanded(
              child: _buildTextField('CHECKED BY', proj.checkedBy, (v) {
                updateProj(proj.copyWith(checkedBy: v));
              }),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildDatePickerField('DATE', proj.effectiveCheckedDate, (v) {
                updateProj(proj.copyWith(checkedDate: v));
              }),
            ),
          ],
        ),

        Row(
          children: [
            Expanded(
              child: _buildTextField('APPROVED BY', proj.approvedBy, (v) {
                updateProj(proj.copyWith(approvedBy: v));
              }),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildDatePickerField('DATE', proj.effectiveApprovedDate, (v) {
                updateProj(proj.copyWith(approvedDate: v));
              }),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDatePickerField(String label, String value, ValueChanged<String> onChanged) {
    final isLight = widget.isLightTheme;
    final displayDate = value.isNotEmpty ? value : DdsProjectInfo.formattedToday;

    return Container(
      margin: const EdgeInsets.only(bottom: 10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isLight ? const Color(0xFF475569) : const Color(0xFF94A3B8),
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4.0),
          InkWell(
            onTap: () async {
              DateTime initialDate = DateTime.now();
              try {
                if (displayDate.contains('/')) {
                  final parts = displayDate.split('/');
                  if (parts.length == 3) {
                    initialDate = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
                  }
                } else if (displayDate.contains('-')) {
                  initialDate = DateTime.parse(displayDate);
                }
              } catch (_) {}

              final picked = await showDatePicker(
                context: context,
                initialDate: initialDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2035),
                builder: (context, child) {
                  return Theme(
                    data: isLight
                        ? ThemeData.light().copyWith(
                            colorScheme: const ColorScheme.light(
                              primary: Color(0xFF0F172A),
                              onPrimary: Colors.white,
                              surface: Colors.white,
                              onSurface: Color(0xFF0F172A),
                            ),
                          )
                        : ThemeData.dark().copyWith(
                            colorScheme: const ColorScheme.dark(
                              primary: Color(0xFF38BDF8),
                              onPrimary: Color(0xFF0F172A),
                              surface: Color(0xFF1E293B),
                              onSurface: Colors.white,
                            ),
                          ),
                    child: child!,
                  );
                },
              );

              if (picked != null) {
                final day = picked.day.toString().padLeft(2, '0');
                final month = picked.month.toString().padLeft(2, '0');
                final formatted = '$day/$month/${picked.year}';
                onChanged(formatted);
              }
            },
            borderRadius: BorderRadius.circular(4.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
              decoration: BoxDecoration(
                color: isLight ? Colors.white : const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(4.0),
                border: Border.all(color: isLight ? const Color(0xFFE2E8F0) : const Color(0xFF334155)),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today, size: 14.0, color: isLight ? const Color(0xFF0284C7) : const Color(0xFF38BDF8)),
                  const SizedBox(width: 8.0),
                  Expanded(
                    child: Text(
                      displayDate,
                      style: TextStyle(
                        color: isLight ? const Color(0xFF0F172A) : Colors.white,
                        fontSize: 12.0,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, String value, ValueChanged<String> onChanged) {
    final isLight = widget.isLightTheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isLight ? const Color(0xFF475569) : const Color(0xFF94A3B8),
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4.0),
          TextFormField(
            initialValue: value,
            style: TextStyle(color: isLight ? const Color(0xFF0F172A) : Colors.white, fontSize: 12.0),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
              filled: true,
              fillColor: isLight ? Colors.white : const Color(0xFF1E293B),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4.0),
                borderSide: BorderSide(color: isLight ? const Color(0xFFCBD5E1) : const Color(0xFF334155)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4.0),
                borderSide: BorderSide(color: isLight ? const Color(0xFFE2E8F0) : const Color(0xFF334155)),
              ),
            ),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildOrderTraceabilityView(DdsProductInstance? instance) {
    final order = instance?.orderLine;
    final isLight = widget.isLightTheme;

    if (order == null) {
      return Center(
        child: Text(
          'No Excel order metadata for this item.',
          style: TextStyle(color: isLight ? const Color(0xFF64748B) : const Color(0xFF94A3B8), fontSize: 12.0),
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
    final isLight = widget.isLightTheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 8.0),
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(4.0),
        border: Border.all(color: isLight ? const Color(0xFFE2E8F0) : const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isLight ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
              fontSize: 10.0,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2.0),
          Text(
            value,
            style: TextStyle(
              color: isLight ? const Color(0xFF0F172A) : Colors.white,
              fontSize: 12.0,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingNavigationHud() {
    final isLight = widget.isLightTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: isLight ? Colors.white.withValues(alpha: 0.95) : const Color(0xFF1E293B).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20.0),
        border: Border.all(color: isLight ? const Color(0xFFCBD5E1) : const Color(0xFF334155)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isLight ? 0.08 : 0.3),
            blurRadius: 10.0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_ios, size: 14, color: isLight ? const Color(0xFF334155) : Colors.white),
            onPressed: _activeSheetIndex > 0
                ? () {
                    setState(() => _activeSheetIndex--);
                    _evaluateActiveSheet();
                  }
                : null,
          ),
          Text(
            'Sheet ${_activeSheetIndex + 1} of ${_document.totalSheets}',
            style: TextStyle(
              color: isLight ? const Color(0xFF0F172A) : Colors.white,
              fontSize: 12.0,
              fontWeight: FontWeight.bold,
            ),
          ),
          IconButton(
            icon: Icon(Icons.arrow_forward_ios, size: 14, color: isLight ? const Color(0xFF334155) : Colors.white),
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
