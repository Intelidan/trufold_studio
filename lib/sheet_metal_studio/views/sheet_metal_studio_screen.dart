// =============================================================================
// sheet_metal_studio_screen.dart
//
// Dual-Viewport Side-by-Side Studio Screen for truFold Studio by Danish.
// Inspired by SolidWorks / DraftSight sheet metal workflow:
// - Left: 2D Unfolded Drawing Canvas (Dynamic fold projection, CAD layers)
// - Middle: Interactive Draggable Split-Pane Divider
// - Right: 3D Shaded Folded Mesh Viewport (Turntable orbit, wireframe toggle)
// - Bottom: Fold Progression Slider (0% Flat to 100% Folded)
// - Header: Undo/Redo (Ctrl+Z/Ctrl+Y), Export/Import, Sample Loaders
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../viewmodels/sheet_metal_studio_viewmodel.dart';
import '../models/dsf_document.dart';
import 'widgets/unfolded_canvas_widget.dart';
import 'widgets/viewport_3d_widget.dart';
import 'widgets/split_pane_divider.dart';
import 'widgets/fold_progress_slider.dart';
import 'widgets/studio/studio_ribbon_toolbar.dart';
import 'widgets/studio/studio_browser_panel.dart';
import '../models/studio_tab_model.dart';
import '../services/studio_file_service.dart';
import '../services/studio_clipboard_service.dart';
import '../models/sheet_metal_material.dart';
import '../engine/dxf_exporter.dart';
import '../engine/dxf_mini_parser.dart';
import '../engine/dxf_import_diagnostics_engine.dart';
import '../engine/dxf_geometry_recognition_engine.dart';
import 'widgets/dxf_import_diagnostics_dialog.dart';
import 'widgets/dxf_fitting_parameter_dialog.dart';
import 'widgets/cad_property_inspector.dart';
import 'widgets/guided_cms/cms_dxf_inspector_dialog.dart';
import 'widgets/guided_cms/cms_guided_stage_card.dart';
import 'widgets/guided_cms/cms_live_learned_card.dart';
import 'widgets/guided_cms/cms_ambiguity_resolver_dialog.dart';
import 'widgets/guided_cms/cms_teach_scaling_overlay.dart';
import '../models/cms/cms_ux_state.dart';
import '../models/cms/cms_product_contract.dart';


class SheetMetalStudioScreen extends StatefulWidget {
  final DsfDocument? initialDocument;

  const SheetMetalStudioScreen({super.key, this.initialDocument});

  static Future<void> open(BuildContext context, {DsfDocument? initialDocument}) {
    return Navigator.of(context).push(MaterialPageRoute(builder: (_) => SheetMetalStudioScreen(initialDocument: initialDocument)));
  }

  @override
  State<SheetMetalStudioScreen> createState() => _SheetMetalStudioScreenState();
}

class _SheetMetalStudioScreenState extends State<SheetMetalStudioScreen> {
  late final List<StudioTab> _tabs;
  int _activeTabIndex = 0;
  final FocusNode _focusNode = FocusNode();
  bool _showPartsTree = true;
  double _browserWidth = 260.0;
  Offset _browserPosition = const Offset(16, 16);
  Offset? _fittingInspectorOffset;
  Offset? _fittingInspectorDragStart;

  Offset _inspectorPosition = const Offset(320, 80);
  bool _isInspectorCollapsed = false;
  Offset? _inspectorDragStartGlobal;
  Offset? _inspectorDragStartPanel;

  SheetMetalStudioViewModel get _viewModel => _tabs[_activeTabIndex].viewModel;
  @visibleForTesting
  SheetMetalStudioViewModel get viewModel => _viewModel;

  @override
  void initState() {
    super.initState();
    final initialDoc = widget.initialDocument ?? DsfDocument.sampleCableTray();
    final tabName = widget.initialDocument != null ? (initialDoc.itemName.isNotEmpty ? '${initialDoc.itemName}.dsf' : 'Part_1.dsf') : 'CT-100x50x3000.dsf';
    _tabs = [
      StudioTab(
        id: 'TAB_${DateTime.now().microsecondsSinceEpoch}',
        title: tabName,
        viewModel: SheetMetalStudioViewModel(initialDocument: initialDoc),
      ),
    ];
  }

  @override
  void dispose() {
    _focusNode.dispose();
    for (final t in _tabs) {
      t.dispose();
    }
    super.dispose();
  }

  void _handleNewTab() {
    final idx = _tabs.length + 1;
    final newDoc = StudioFileService.createBlankDsf(itemName: 'Part_$idx');
    final tab = StudioTab(
      id: 'TAB_${DateTime.now().microsecondsSinceEpoch}',
      title: 'Part_$idx.dsf',
      viewModel: SheetMetalStudioViewModel(initialDocument: newDoc),
    );
    setState(() {
      _tabs.add(tab);
      _activeTabIndex = _tabs.length - 1;
    });
  }

  Future<void> _handleCloseTab(int index) async {
    if (index < 0 || index >= _tabs.length) return;
    final tabToClose = _tabs[index];
    final isModified = tabToClose.isModified || tabToClose.viewModel.isModified;

    if (isModified && mounted) {
      final result = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            children: const [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFEAB308), size: 24),
              SizedBox(width: 8),
              Text('Unsaved Changes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text('Do you want to save the changes to "${tabToClose.title}" before closing?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('cancel'),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('dont_save'),
              child: const Text("Don't Save", style: TextStyle(color: Color(0xFFEF4444))),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop('save'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
              child: const Text('Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      if (result == null || result == 'cancel') {
        return;
      }

      if (result == 'save') {
        final prevActive = _activeTabIndex;
        _activeTabIndex = index;
        final saved = await _handleSaveActiveFile();
        _activeTabIndex = prevActive;
        if (!saved) return;
      }
    }

    if (_tabs.length <= 1) {
      _handleNewTab();
      final old = _tabs.removeAt(0);
      old.dispose();
      _activeTabIndex = 0;
      setState(() {});
      return;
    }
    final tab = _tabs.removeAt(index);
    tab.dispose();
    if (_activeTabIndex >= _tabs.length) {
      _activeTabIndex = _tabs.length - 1;
    }
    setState(() {});
  }

  Future<void> _handleOpenFile() async {
    final rawFiles = await StudioFileService.pickRawFiles();
    if (rawFiles.isEmpty) return;

    for (final file in rawFiles) {
      final isDxf = file.fileName.toLowerCase().endsWith('.dxf');
      if (isDxf) {
        final parsed = DxfMiniParser.parse(file.content);
        final report = DxfImportDiagnosticsEngine.analyze(parsed);
        bool shouldHeal = true;
        if (mounted) {
          final chosenHeal = await DxfImportDiagnosticsDialog.show(context, report: report, fileName: file.fileName);
          if (chosenHeal == null) {
            // User cancelled this file
            continue;
          }
          shouldHeal = chosenHeal;
        }

        final dataToRecognize = shouldHeal ? DxfImportDiagnosticsEngine.heal(parsed).healedData : parsed;
        final recognized = DxfGeometryRecognitionEngine.recognize(dataToRecognize, productType: file.fileName.replaceAll('.dxf', ''), itemName: file.fileName);

        final tab = StudioTab(
          id: 'TAB_${DateTime.now().microsecondsSinceEpoch}_${_tabs.length}',
          title: file.fileName,
          filePath: file.filePath,
          viewModel: SheetMetalStudioViewModel(initialDocument: recognized.generatedDocument),
        );
        setState(() {
          _tabs.add(tab);
          _activeTabIndex = _tabs.length - 1;
        });

        // DXF Inspector: "Is this a CMS Part Drawing?" (Clean 3D Discovery)
        if (mounted) {
          final contract = await CmsDxfInspectorDialog.show(context, fileName: file.fileName);
          if (contract != null && mounted) {
            tab.viewModel.startCleanCmsDiscovery(contract: contract);
          }
        }

      } else {
        final items = StudioFileService.parseContent(file.content, fileName: file.fileName, filePath: file.filePath);
        for (final item in items) {
          final tab = StudioTab(
            id: 'TAB_${DateTime.now().microsecondsSinceEpoch}_${_tabs.length}',
            title: item.fileName,
            filePath: item.filePath,
            viewModel: SheetMetalStudioViewModel(initialDocument: item.document),
          );
          _tabs.add(tab);
        }
        if (mounted && _tabs.isNotEmpty) {
          setState(() {
            _activeTabIndex = _tabs.length - 1;
          });
        }
      }
    }
  }

  Future<void> _handleSaveDdsProject() async {
    final docs = _tabs.map((t) => t.viewModel.document).toList();
    final ddsContent = StudioFileService.createDdsString(docs, projectName: 'TruFold Project Assembly');
    final success = await StudioFileService.saveFile(
      fileName: 'Project_Assembly.dds',
      content: ddsContent,
      dialogTitle: 'Save All Tabs to Danish Data Sheet (.dds)',
    );
    if (mounted && success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Successfully exported ${_tabs.length} parts into Project_Assembly.dds!'), backgroundColor: const Color(0xFF0284C7)),
      );
    }
  }

  Future<bool> _handleSaveActiveFile() async {
    if (_activeTabIndex < 0 || _activeTabIndex >= _tabs.length) return false;
    final activeTab = _tabs[_activeTabIndex];
    if (activeTab.filePath != null && activeTab.filePath!.isNotEmpty) {
      // Ctrl+S specifically saves the .dsf file, preserving any underlying raw .dxf
      String targetPath = activeTab.filePath!;
      if (targetPath.toLowerCase().endsWith('.dxf')) {
        targetPath = '${targetPath.substring(0, targetPath.length - 4)}.dsf';
      }
      final doc = _viewModel.prepareDocumentForSave();
      final content = doc.toJsonString(pretty: true);
      final success = await StudioFileService.saveFileDirect(filePath: targetPath, content: content);
      if (mounted && success) {
        activeTab.filePath = targetPath;
        activeTab.title = targetPath.replaceAll('\\', '/').split('/').last;
        activeTab.isModified = false;
        _viewModel.markClean();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved ${activeTab.title} (.dsf) successfully!'),
            backgroundColor: const Color(0xFF059669),
            duration: const Duration(seconds: 2),
          ),
        );
        setState(() {});
        return true;
      }
    }
    return await _handleSaveAsActiveFile();
  }

  Future<bool> _handleSaveAsActiveFile() async {
    if (_activeTabIndex < 0 || _activeTabIndex >= _tabs.length) return false;
    final activeTab = _tabs[_activeTabIndex];
    final doc = _viewModel.prepareDocumentForSave();
    final defaultName = doc.itemName.isNotEmpty
        ? (doc.itemName.endsWith('.dsf') ? doc.itemName : '${doc.itemName}.dsf')
        : (activeTab.title.endsWith('.dsf') ? activeTab.title : '${activeTab.title}.dsf');
    final content = doc.toJsonString(pretty: true);
    final savedPath = await StudioFileService.saveFileAs(fileName: defaultName, content: content, dialogTitle: 'Save Part As ($defaultName)');
    if (mounted && savedPath != null) {
      activeTab.filePath = savedPath;
      final fileBasename = savedPath.replaceAll('\\', '/').split('/').last;
      activeTab.title = fileBasename;
      activeTab.isModified = false;
      _viewModel.markClean();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved as $fileBasename successfully!'), backgroundColor: const Color(0xFF059669), duration: const Duration(seconds: 2)),
      );
      setState(() {});
      return true;
    }
    return false;
  }

  Future<void> _handleCopySelection() async {
    final ok = await StudioClipboardService.copySelection(_viewModel);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok ? 'Copied ${StudioClipboardService.currentLabel} to clipboard!' : 'No CAD feature selected to copy. Select a punch, pattern, bend, or cut line.',
          ),
          backgroundColor: ok ? const Color(0xFF0284C7) : const Color(0xFF64748B),
          duration: const Duration(seconds: 2),
        ),
      );
      setState(() {});
    }
  }

  Future<void> _handlePasteClipboard() async {
    final res = await StudioClipboardService.pasteInto(_viewModel);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res ?? 'Clipboard is empty or does not contain compatible CAD primitives.'),
          backgroundColor: res != null ? const Color(0xFF059669) : const Color(0xFFD97706),
          duration: const Duration(seconds: 2),
        ),
      );
      setState(() {});
    }
  }

  bool _isEditingText() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return false;
    final ctx = focus.context;
    if (ctx == null || !ctx.mounted) return false;
    if (ctx.widget is EditableText) return true;
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  void _handleEscapeKey(BuildContext context) {
    // 1. Pop any open modal dialog / bottom sheet / route first
    final rootNav = Navigator.of(context, rootNavigator: true);
    if (rootNav.canPop()) {
      rootNav.pop();
      return;
    }
    final localNav = Navigator.of(context);
    if (localNav.canPop()) {
      localNav.pop();
      return;
    }

    // 2. Close floating property / fitting / constraint inspectors if open
    bool closedPanel = false;
    if (_viewModel.isPropertyInspectorOpen) {
      _viewModel.setPropertyInspectorOpen(false);
      closedPanel = true;
    }
    if (_viewModel.isFittingInspectorOpen) {
      _viewModel.setFittingInspectorOpen(false);
      closedPanel = true;
    }
    if (_viewModel.isConstraintManagerOpen) {
      _viewModel.toggleConstraintManager();
      closedPanel = true;
    }
    if (closedPanel) {
      setState(() {});
      return;
    }

    // 3. Deselect any active CAD selections
    final hasSelection =
        _viewModel.selectedBendId != null ||
        _viewModel.selectedPunchId != null ||
        _viewModel.selectedCutId != null ||
        _viewModel.selectedPatternId != null ||
        _viewModel.selectedArcId != null ||
        _viewModel.selectedDimensionId != null ||
        _viewModel.selectedEntityIds.isNotEmpty;
    if (hasSelection) {
      _viewModel.deselectAll();
      setState(() {});
      return;
    }

    // 4. Reset active tool back to select
    if (_viewModel.toolMode != StudioToolMode.select) {
      _viewModel.setToolMode(StudioToolMode.select);
      setState(() {});
    }
  }

  Widget _buildCanvasTopTipBanner(SheetMetalStudioViewModel vm) {
    if (vm.toolMode == StudioToolMode.select || vm.toolMode == StudioToolMode.pan) {
      return const SizedBox.shrink();
    }

    Widget content;
    Color accentColor = const Color(0xFF0284C7);

    switch (vm.toolMode) {
      case StudioToolMode.addBend:
      case StudioToolMode.addFlange:
        accentColor = const Color(0xFF0284C7);
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () {
                vm.toggleAutoBendPlacement();
                setState(() {});
              },
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: vm.autoBendPlacementEnabled ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(vm.autoBendPlacementEnabled ? Icons.bolt : Icons.power_settings_new, size: 13, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(
                      'Auto Edge: ${vm.autoBendPlacementEnabled ? "ON" : "OFF"}',
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Press [Ctrl] to toggle Auto • Click edge to auto-place, or Drag to draw line • [Esc] cancel',
              style: TextStyle(fontSize: 11, color: Color(0xFF334155), fontWeight: FontWeight.w500),
            ),
          ],
        );
        break;

      case StudioToolMode.drawCircle:
        accentColor = const Color(0xFF2563EB);
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFFDBEAFE), borderRadius: BorderRadius.circular(4)),
              child: Text(
                'Hole Preset: ${vm.activeToolConfig.selectedPunchPreset} (Ø${vm.activeToolConfig.roundHoleDiameter.toStringAsFixed(1)}mm)',
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF1E40AF)),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Click blank to stamp hole preset • Or drag to draw custom circle • [Esc] to exit',
              style: TextStyle(fontSize: 11, color: Color(0xFF334155), fontWeight: FontWeight.w500),
            ),
          ],
        );
        break;

      case StudioToolMode.drawRectangle:
        accentColor = const Color(0xFF2563EB);
        final w = vm.activeToolConfig.rectWidth.toStringAsFixed(1);
        final h = vm.activeToolConfig.rectHeight.toStringAsFixed(1);
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFFDBEAFE), borderRadius: BorderRadius.circular(4)),
              child: Text(
                'Square/Rect Punch: $w×${h}mm',
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF1E40AF)),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Click blank to stamp square punch preset • Or drag to draw custom rectangle • [Esc] to exit',
              style: TextStyle(fontSize: 11, color: Color(0xFF334155), fontWeight: FontWeight.w500),
            ),
          ],
        );
        break;

      case StudioToolMode.setBaseAnchor:
        accentColor = const Color(0xFFD97706);
        content = const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.anchor, size: 14, color: Color(0xFFD97706)),
            SizedBox(width: 6),
            Text(
              'Set Base Floor Anchor: Click any face or boundary edge to fix stationary face for 3D folding • [Esc] to exit',
              style: TextStyle(fontSize: 11, color: Color(0xFF334155), fontWeight: FontWeight.w600),
            ),
          ],
        );
        break;

      case StudioToolMode.perforationPattern:
        accentColor = const Color(0xFF0D9488);
        content = const Text(
          'Perforation Pattern: Drag bounding box to generate hole matrix • [Esc] to exit',
          style: TextStyle(fontSize: 11, color: Color(0xFF334155), fontWeight: FontWeight.w500),
        );
        break;

      default:
        content = Text(
          'Active Tool: ${vm.toolMode.name} • Press [Esc] to cancel',
          style: const TextStyle(fontSize: 11, color: Color(0xFF334155), fontWeight: FontWeight.w500),
        );
    }

    return Positioned(
      top: 10,
      left: 16,
      right: 16,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accentColor.withValues(alpha: 0.4), width: 1.0),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: content,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () {
          if (_viewModel.canUndo) _viewModel.undo();
        },
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): () {
          if (_viewModel.canUndo) _viewModel.undo();
        },
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): () {
          if (_viewModel.canRedo) _viewModel.redo();
        },
        const SingleActivator(LogicalKeyboardKey.keyY, meta: true): () {
          if (_viewModel.canRedo) _viewModel.redo();
        },
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): () {
          if (_viewModel.canRedo) _viewModel.redo();
        },
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true): () {
          if (_viewModel.canRedo) _viewModel.redo();
        },
        SingleActivator(LogicalKeyboardKey.escape): () => _handleEscapeKey(context),
        SingleActivator(LogicalKeyboardKey.keyA, control: true): () {
          _viewModel.selectAll();
          setState(() {});
        },
        SingleActivator(LogicalKeyboardKey.keyA, meta: true): () {
          _viewModel.selectAll();
          setState(() {});
        },
        const SingleActivator(LogicalKeyboardKey.keyC, control: true): _handleCopySelection,
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true): _handleCopySelection,
        const SingleActivator(LogicalKeyboardKey.keyV, control: true): _handlePasteClipboard,
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true): _handlePasteClipboard,
        const SingleActivator(LogicalKeyboardKey.keyT, control: true): _handleNewTab,
        const SingleActivator(LogicalKeyboardKey.keyT, meta: true): _handleNewTab,
        const SingleActivator(LogicalKeyboardKey.keyW, control: true): () => _handleCloseTab(_activeTabIndex),
        const SingleActivator(LogicalKeyboardKey.keyW, meta: true): () => _handleCloseTab(_activeTabIndex),
        const SingleActivator(LogicalKeyboardKey.keyO, control: true): _handleOpenFile,
        const SingleActivator(LogicalKeyboardKey.keyO, meta: true): _handleOpenFile,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _handleSaveActiveFile,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _handleSaveActiveFile,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true): _handleSaveAsActiveFile,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true, shift: true): _handleSaveAsActiveFile,
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: (node, event) {
          // Ctrl key down alone while in addBend or addFlange mode toggles Auto Edge Placement
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.controlLeft || event.logicalKey == LogicalKeyboardKey.controlRight) {
              if (_viewModel.toolMode == StudioToolMode.addBend || _viewModel.toolMode == StudioToolMode.addFlange) {
                _viewModel.toggleAutoBendPlacement();
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Auto Edge Detection: ${_viewModel.autoBendPlacementEnabled ? "ON" : "OFF"} (Ctrl to toggle)',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    backgroundColor: _viewModel.autoBendPlacementEnabled ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                    duration: const Duration(milliseconds: 1200),
                  ),
                );
                setState(() {});
                return KeyEventResult.handled;
              }
            }
          }

          if (event is KeyDownEvent || event is KeyRepeatEvent) {
            final isShift = HardwareKeyboard.instance.isShiftPressed;
            final isCtrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
            final step = isShift ? 5.0 : (isCtrl ? 0.1 : 0.5);

            // Never intercept typing shortcuts when editing text fields or port editors
            if (_isEditingText()) {
              return KeyEventResult.ignored;
            }

            final hasSelection =
                _viewModel.selectedBendId != null ||
                _viewModel.selectedPunchId != null ||
                _viewModel.selectedCutId != null ||
                _viewModel.selectedPatternId != null ||
                _viewModel.selectedArcId != null;

            if (event.logicalKey == LogicalKeyboardKey.delete || event.logicalKey == LogicalKeyboardKey.backspace) {
              if (_viewModel.selectedConstraintId != null) {
                _viewModel.removeConstraint(_viewModel.selectedConstraintId!);
                return KeyEventResult.handled;
              }
              if (_viewModel.selectedDimensionId != null) {
                _viewModel.removeDimension(_viewModel.selectedDimensionId!);
                return KeyEventResult.handled;
              }
              _viewModel.deleteSelectedEntities();
              return KeyEventResult.handled;
            }

            if (event.logicalKey == LogicalKeyboardKey.escape) {
              _handleEscapeKey(context);
              return KeyEventResult.handled;
            }

            if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyA) {
              _viewModel.selectAll();
              setState(() {});
              return KeyEventResult.handled;
            }

            // CAD Tool Shortcuts (KeyDown only, no Ctrl/Meta)
            if (event is KeyDownEvent && !isCtrl) {
              if (event.logicalKey == LogicalKeyboardKey.keyB) {
                _viewModel.setToolMode(StudioToolMode.addBend);
                setState(() {});
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.keyF) {
                _viewModel.setToolMode(isShift ? StudioToolMode.cornerFillet : StudioToolMode.addFlange);
                setState(() {});
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.keyM) {
                _viewModel.setToolMode(StudioToolMode.addCut);
                setState(() {});
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.keyL) {
                _viewModel.setToolMode(StudioToolMode.drawPolyline);
                setState(() {});
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.keyG) {
                _viewModel.setToolMode(StudioToolMode.drawRectangle);
                setState(() {});
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.keyC) {
                _viewModel.setToolMode(isShift ? StudioToolMode.cornerChamfer : StudioToolMode.drawCircle);
                setState(() {});
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.keyA && !isShift) {
                _viewModel.setToolMode(StudioToolMode.drawArc);
                setState(() {});
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.keyQ) {
                _viewModel.toggleSelectedConstruction();
                setState(() {});
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.keyD) {
                _viewModel.setToolMode(StudioToolMode.addDimension);
                setState(() {});
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.keyP) {
                _viewModel.setToolMode(StudioToolMode.perforationPattern);
                setState(() {});
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.keyV || event.logicalKey == LogicalKeyboardKey.space) {
                _viewModel.setToolMode(StudioToolMode.select);
                setState(() {});
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.keyH) {
                _viewModel.setToolMode(StudioToolMode.pan);
                setState(() {});
                return KeyEventResult.handled;
              }
            }

            if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              if (hasSelection) {
                _viewModel.nudgeSelected(-step, 0.0);
              } else {
                _viewModel.pan2DCanvas(Offset(step * 25.0, 0.0));
              }
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              if (hasSelection) {
                _viewModel.nudgeSelected(step, 0.0);
              } else {
                _viewModel.pan2DCanvas(Offset(-step * 25.0, 0.0));
              }
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              if (hasSelection) {
                _viewModel.nudgeSelected(0.0, -step);
              } else {
                _viewModel.pan2DCanvas(Offset(0.0, step * 25.0));
              }
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
              if (hasSelection) {
                _viewModel.nudgeSelected(0.0, step);
              } else {
                _viewModel.pan2DCanvas(Offset(0.0, -step * 25.0));
              }
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTapDown: (_) {
            if (!_focusNode.hasFocus) {
              _focusNode.requestFocus();
            }
          },
          child: Scaffold(
            backgroundColor: const Color(0xFFF8FAFC),
            body: SafeArea(
              child: ListenableBuilder(
                listenable: _viewModel,
                builder: (context, _) {
                  return Column(
                    children: [
                      // truFold Studio Ribbon Toolbar
                      StudioRibbonToolbar(
                        viewModel: _viewModel,
                        tabs: _tabs,
                        activeTabIndex: _activeTabIndex,
                        onTabSelected: (idx) => setState(() => _activeTabIndex = idx),
                        onTabClosed: _handleCloseTab,
                        onNewTab: _handleNewTab,
                        onOpenFile: _handleOpenFile,
                        onSaveFile: _handleSaveActiveFile,
                        onSaveAsFile: _handleSaveAsActiveFile,
                        onSaveDdsProject: _handleSaveDdsProject,
                        onExportDxf: () => _exportQuickFlatDxf(context),
                        onMaterialDialog: () => _showMaterialDialog(context),
                        onLoadSampleBracket: _loadSampleBracket,
                        onFittingDetails: () => _viewModel.setPropertyInspectorOpen(true),
                        onLoadSampleTray: () => _viewModel.loadSampleCableTray(width: 100, height: 50, length: 3000),
                        onFinishSketch: () {
                          _viewModel.setToolMode(StudioToolMode.select);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('✓ Sketch1 Finished. Profile & Features updated.'),
                              backgroundColor: Color(0xFF16A34A),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),

                      // 2. Main Workspace (Draggable Dual-Viewport + Floating Glass Browser)
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final totalW = constraints.maxWidth;
                            final totalH = constraints.maxHeight;
                            const dividerW = 14.0;
                            final availableW = (totalW - dividerW).clamp(200.0, double.infinity);

                            final leftW = (availableW * _viewModel.splitRatio).clamp(100.0, availableW - 100.0);
                            final rightW = availableW - leftW;

                            return Stack(
                              children: [
                                Row(
                                  children: [
                                    // Left Viewport: 2D Unfolded Flat Pattern (CAD Sketch View)
                                    SizedBox(
                                      width: leftW,
                                      child: ClipRect(
                                        child: Stack(
                                          children: [
                                            UnfoldedCanvasWidget(viewModel: _viewModel, renderFloatingInspectors: false, showInCanvasToolRibbon: false),
                                            _buildCanvasTopTipBanner(_viewModel),
                                          ],
                                        ),
                                      ),
                                    ),

                                    // Draggable Split Divider
                                    SplitPaneDivider(
                                      splitRatio: _viewModel.splitRatio,
                                      onRatioChanged: _viewModel.setSplitRatio,
                                      onDoubleTapReset: () => _viewModel.setSplitRatio(0.50),
                                    ),

                                    // Right Viewport: 3D Folded Mesh
                                    SizedBox(
                                      width: rightW,
                                      child: ClipRect(child: Viewport3dWidget(viewModel: _viewModel)),
                                    ),
                                  ],
                                ),

                                // Floating Transparent Draggable BROWSER Panel
                                if (_showPartsTree)
                                  Positioned(
                                    left: _browserPosition.dx.clamp(8.0, math.max(8.0, totalW - _browserWidth - 10)),
                                    top: _browserPosition.dy.clamp(8.0, math.max(8.0, totalH - 120.0)),
                                    child: SizedBox(
                                      height: math.min(totalH - 32.0, 540.0),
                                      child: StudioBrowserPanel(
                                        viewModel: _viewModel,
                                        width: _browserWidth,
                                        onWidthChanged: (delta) {
                                          setState(() {
                                            _browserWidth = (_browserWidth + delta).clamp(200.0, math.max(220.0, totalW * 0.45));
                                          });
                                        },
                                        onPositionDelta: (delta) {
                                          setState(() {
                                            _browserPosition = Offset(
                                              (_browserPosition.dx + delta.dx).clamp(0.0, math.max(0.0, totalW - _browserWidth)),
                                              (_browserPosition.dy + delta.dy).clamp(0.0, math.max(0.0, totalH - 60)),
                                            );
                                          });
                                        },
                                        onClose: () => setState(() => _showPartsTree = false),
                                        onEditThickness: () => _showThicknessDialog(context),
                                        onEditMaterial: () => _showMaterialDialog(context),
                                      ),
                                    ),
                                  )
                                else
                                  Positioned(
                                    left: 12,
                                    top: 12,
                                    child: InkWell(
                                      onTap: () => setState(() => _showPartsTree = true),
                                      borderRadius: BorderRadius.circular(6),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.85),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: const Color(0xFFCBD5E1), width: 1.0),
                                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 6, offset: const Offset(0, 2))],
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.folder_open, size: 14, color: Color(0xFF0284C7)),
                                            SizedBox(width: 5),
                                            Text(
                                              'BROWSER',
                                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: Color(0xFF334155)),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),

                                // Draggable Floating DSF Fitting Parameter Inspector (Spans across both viewports)
                                if (_viewModel.isFittingInspectorOpen)
                                  Positioned(
                                    left: (_fittingInspectorOffset?.dx ?? (totalW - 710) / 2).clamp(8.0, math.max(8.0, totalW - 720.0)),
                                    top: (_fittingInspectorOffset?.dy ?? 24.0).clamp(8.0, math.max(8.0, constraints.maxHeight - 590.0)),
                                    child: Material(
                                      color: Colors.transparent,
                                      elevation: 16,
                                      shadowColor: Colors.black.withValues(alpha: 0.35),
                                      borderRadius: BorderRadius.circular(12),
                                      child: DxfFittingParameterDialog(
                                        viewModel: _viewModel,
                                        onClose: () => _viewModel.setFittingInspectorOpen(false),
                                        onDragStartHeader: (details) {
                                          _fittingInspectorDragStart = details.globalPosition - (_fittingInspectorOffset ?? Offset((totalW - 710) / 2, 24.0));
                                        },
                                        onDragHeader: (details) {
                                          if (_fittingInspectorDragStart != null) {
                                            setState(() {
                                              _fittingInspectorOffset = details.globalPosition - _fittingInspectorDragStart!;
                                            });
                                          }
                                        },
                                      ),
                                    ),
                                  ),

                                // Clean CMS Architecture: Autonomous Guided Stage Card & Live Learned Narrative
                                AnimatedBuilder(
                                  animation: _viewModel.cmsGuidedController,
                                  builder: (context, _) {
                                    final cmsCtrl = _viewModel.cmsGuidedController;
                                    if (cmsCtrl.phase == CmsUxPhase.idle) return const SizedBox.shrink();

                                    return Positioned(
                                      top: 16.0,
                                      left: 16.0,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          CmsGuidedStageCard(
                                            controller: cmsCtrl,
                                            onStartAnalysis: () => _viewModel.startCleanCmsDiscovery(contract: cmsCtrl.state.contract),
                                            onUseSuggestedBends: () => _viewModel.applyUserBends(),
                                            onEditBendsManually: () => _viewModel.setToolMode(StudioToolMode.addBend),
                                            onFinalizeTemplate: () => _viewModel.finalizeCmsTemplate(),
                                            onStartTeachScaling: () => _viewModel.startTeachScaling(),
                                            onDismiss: () => cmsCtrl.reset(),
                                          ),
                                          const SizedBox(height: 10.0),
                                          CmsLiveLearnedCard(controller: cmsCtrl),
                                        ],
                                      ),
                                    );
                                  },
                                ),

                                // Clean CMS Architecture: Phase 2 Teach Scaling Overlay
                                AnimatedBuilder(
                                  animation: _viewModel,
                                  builder: (context, _) {
                                    if (!_viewModel.isTeachScalingActive || _viewModel.scalingController == null) {
                                      return const SizedBox.shrink();
                                    }

                                    return Positioned(
                                      top: 16.0,
                                      left: 16.0,
                                      child: CmsTeachScalingOverlay(
                                        controller: _viewModel.scalingController!,
                                        onAccept: () => _viewModel.acceptTeachScaling(),
                                        onCancel: () => _viewModel.exitTeachScaling(),
                                      ),
                                    );
                                  },
                                ),

                                // Clean CMS Architecture: Exception Ambiguity Resolver Dialog
                                AnimatedBuilder(
                                  animation: _viewModel.cmsGuidedController,
                                  builder: (context, _) {
                                    final cmsCtrl = _viewModel.cmsGuidedController;
                                    if (cmsCtrl.phase != CmsUxPhase.ambiguityRequired) return const SizedBox.shrink();

                                    return Positioned.fill(
                                      child: Container(
                                        color: Colors.black.withValues(alpha: 0.35),
                                        child: Center(
                                          child: CmsAmbiguityResolverDialog(
                                            contract: cmsCtrl.state.contract ?? CmsProductContract.bend45,
                                            candidateOpenings: cmsCtrl.state.candidateOpenings,
                                            onResolved: (ports) => cmsCtrl.resolveAmbiguity(ports),
                                            onCancel: () => cmsCtrl.reset(),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),

                                // Draggable Floating CAD Property Inspector (Spans across 2D and 3D viewports)
                                if (_viewModel.isPropertyInspectorOpen &&
                                    (_viewModel.selectedBendId != null ||
                                        _viewModel.selectedCutId != null ||
                                        _viewModel.selectedPunchId != null ||
                                        _viewModel.selectedPatternId != null ||
                                        _viewModel.selectedDimensionId != null ||
                                        _viewModel.selectedArcId != null ||
                                        _viewModel.selectedFaceId != null ||
                                        (_viewModel.isTemplateActive && _viewModel.activeTemplate != null) ||
                                        (_viewModel.toolMode != StudioToolMode.select &&
                                            _viewModel.toolMode != StudioToolMode.pan &&
                                            _viewModel.toolMode != StudioToolMode.addCut &&
                                            _viewModel.toolMode != StudioToolMode.setBaseAnchor)))
                                  Positioned(
                                    left: _inspectorPosition.dx.clamp(8.0, math.max(8.0, totalW - 290.0)),
                                    top: _inspectorPosition.dy.clamp(8.0, math.max(8.0, totalH - 120.0)),
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onPanStart: (details) {
                                        _inspectorDragStartGlobal = details.globalPosition;
                                        _inspectorDragStartPanel = _inspectorPosition;
                                      },
                                      onPanUpdate: (details) {
                                        if (_inspectorDragStartGlobal != null && _inspectorDragStartPanel != null) {
                                          setState(() {
                                            _inspectorPosition = _inspectorDragStartPanel! + (details.globalPosition - _inspectorDragStartGlobal!);
                                          });
                                        }
                                      },
                                      child: CadPropertyInspector(
                                        viewModel: _viewModel,
                                        isCollapsed: _isInspectorCollapsed,
                                        onToggleCollapse: () {
                                          setState(() {
                                            _isInspectorCollapsed = !_isInspectorCollapsed;
                                          });
                                        },
                                        onClose: () {
                                          _viewModel.setPropertyInspectorOpen(false);
                                        },
                                        onDragStartHeader: (details) {
                                          _inspectorDragStartGlobal = details.globalPosition;
                                          _inspectorDragStartPanel = _inspectorPosition;
                                        },
                                        onDragHeader: (details) {
                                          if (_inspectorDragStartGlobal != null && _inspectorDragStartPanel != null) {
                                            setState(() {
                                              _inspectorPosition = _inspectorDragStartPanel! + (details.globalPosition - _inspectorDragStartGlobal!);
                                            });
                                          }
                                        },
                                      ),
                                    ),
                                  ),

                                // Floating Reopen Button if Inspector is closed but an item is selected
                                if (!_viewModel.isPropertyInspectorOpen &&
                                    (_viewModel.selectedBendId != null ||
                                        _viewModel.selectedCutId != null ||
                                        _viewModel.selectedPunchId != null ||
                                        _viewModel.selectedPatternId != null ||
                                        _viewModel.selectedDimensionId != null ||
                                        _viewModel.selectedArcId != null ||
                                        _viewModel.selectedFaceId != null))
                                  Positioned(
                                    top: 12,
                                    right: 180,
                                    child: InkWell(
                                      onTap: () {
                                        _viewModel.setPropertyInspectorOpen(true);
                                      },
                                      borderRadius: BorderRadius.circular(6),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: const Color(0xFF0284C7)),
                                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0, 2))],
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: const [
                                            Icon(Icons.tune, size: 14, color: Color(0xFF0284C7)),
                                            SizedBox(width: 4),
                                            Text(
                                              'Properties',
                                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),

                      // 3. Bottom Fold Progression Dock (0% Flat to 100% Folded)
                      FoldProgressSlider(viewModel: _viewModel),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showThicknessDialog(BuildContext context) {
    final currentThk = _viewModel.document.material.thicknessMm;
    const presets = [0.8, 1.0, 1.2, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0];
    final controller = TextEditingController(text: currentThk.toStringAsFixed(2));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.line_weight, color: Color(0xFF0284C7), size: 20),
            SizedBox(width: 8),
            Text('Sheet Metal Thickness', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select standard industrial sheet metal thickness gauge or enter a custom value in millimeters:',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: presets.map((thk) {
                  final isSelected = (thk - currentThk).abs() < 1e-3;
                  return ChoiceChip(
                    label: Text('${thk.toStringAsFixed(1)} mm'),
                    selected: isSelected,
                    selectedColor: const Color(0xFFE0F2FE),
                    labelStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF334155),
                    ),
                    onSelected: (_) {
                      _viewModel.setSheetThickness(thk);
                      Navigator.of(ctx).pop();
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Custom Thickness (mm)', border: OutlineInputBorder(), isDense: true),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7), foregroundColor: Colors.white),
            onPressed: () {
              final val = double.tryParse(controller.text);
              if (val != null && val > 0) {
                _viewModel.setSheetThickness(val);
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  void _showMaterialDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final currentMat = _viewModel.document.material;
          final currentDef = currentMat.toDefinition();
          final currentGrade = currentDef.grade;
          final currentFinish = currentDef.finish;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Row(
              children: const [
                Icon(Icons.science_outlined, color: Color(0xFF0284C7), size: 20),
                SizedBox(width: 8),
                Text(
                  'Sheet Metal Material & Properties',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
              ],
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Configure base metal alloy and independent surface coating finish. Density, K-factor, bend allowances, and minimum radii adapt dynamically.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 16),

                    // Section 1: 7 Base Material Grades
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'BASE ALLOY GRADE',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: Color(0xFF475569)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: const Color(0xFFE0F2FE), borderRadius: BorderRadius.circular(4)),
                          child: const Text(
                            '7 Standard Alloys',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    Container(
                      constraints: const BoxConstraints(maxHeight: 220),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: SheetMetalMaterialGrade.values.length,
                        separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        itemBuilder: (ctx, i) {
                          final grade = SheetMetalMaterialGrade.values[i];
                          final isSelected = currentGrade == grade;
                          return InkWell(
                            onTap: () {
                              _viewModel.setMaterialDefinition(grade: grade, finish: currentFinish);
                              setDialogState(() {});
                            },
                            child: Container(
                              color: isSelected ? const Color(0xFFF0F9FF) : Colors.transparent,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                              child: Row(
                                children: [
                                  Icon(
                                    isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                    size: 16,
                                    color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF94A3B8),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 48,
                                    padding: const EdgeInsets.symmetric(vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isSelected ? const Color(0xFF0284C7) : const Color(0xFFE2E8F0),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      grade.code,
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : const Color(0xFF475569)),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          grade.displayName,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.bold,
                                            color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF0F172A),
                                          ),
                                        ),
                                        Text(
                                          '${grade.densityKgM3.toStringAsFixed(0)} kg/m³ | Min R: ${grade.minBendFactor}×T | K: ${grade.defaultKFactor.toStringAsFixed(2)} | ${grade.tensileStrengthMpa.toStringAsFixed(0)} MPa',
                                          style: const TextStyle(fontSize: 9.5, color: Color(0xFF64748B)),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Section 2: 11 Surface Finishes
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'SURFACE COATING FINISH',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: Color(0xFF475569)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(4)),
                          child: const Text(
                            '11 Coatings',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFB45309)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<CoatingFinish>(
                          value: currentFinish,
                          isExpanded: true,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF0F172A), fontWeight: FontWeight.w600),
                          items: [
                            for (final finish in CoatingFinish.values)
                              DropdownMenuItem(
                                value: finish,
                                child: Text('${finish.code} - ${finish.displayName}', style: const TextStyle(fontSize: 12)),
                              ),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              _viewModel.setCoatingFinish(val);
                              setDialogState(() {});
                            }
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Section 3: Engineering Metrics Card
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Thickness (T): ${_viewModel.document.material.thicknessMm.toStringAsFixed(2)} mm',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF475569), fontWeight: FontWeight.w500),
                              ),
                              Text(
                                'Default K-Factor: ${currentGrade.defaultKFactor.toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF475569), fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Divider(height: 1, color: Color(0xFFE2E8F0)),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Gross Blank: ${_viewModel.partGrossWeightKg.toStringAsFixed(2)} kg',
                                style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                              ),
                              Text(
                                'Net Weight: ${_viewModel.partNetWeightKg.toStringAsFixed(2)} kg',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Apply & Close', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _exportQuickFlatDxf(BuildContext context) async {
    final doc = _viewModel.document;
    final cleanPart = doc.partNumber.isNotEmpty ? doc.partNumber.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_') : 'Flat_Pattern';
    final dxf = DxfExporter.exportDxf(doc);
    Clipboard.setData(ClipboardData(text: dxf));
    final saved = await StudioFileService.saveFile(fileName: '$cleanPart.dxf', content: dxf, dialogTitle: 'Save Flat Pattern DXF ($cleanPart.dxf)');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(saved ? 'Saved $cleanPart.dxf successfully!' : 'Plain 2D Flat Drawing DXF copied to clipboard! (Ready for CNC Laser / Punch CAM)'),
          backgroundColor: const Color(0xFF059669),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _loadSampleBracket() {
    const sampleDxf = '''
0
SECTION
2
ENTITIES
0
LINE
8
EDGES
62
7
10
0.0
20
0.0
11
200.0
21
0.0
0
LINE
8
EDGES
62
7
10
200.0
20
0.0
11
200.0
21
100.0
0
LINE
8
EDGES
62
7
10
200.0
20
100.0
11
0.0
21
100.0
0
LINE
8
EDGES
62
7
10
0.0
20
100.0
11
0.0
21
0.0
0
LINE
8
BEND_UP
62
4
10
50.0
20
0.0
11
50.0
21
100.0
0
LINE
8
BEND_DOWN
62
2
10
150.0
20
0.0
11
150.0
21
100.0
0
CIRCLE
8
HOLES
10
100.0
20
50.0
40
6.0
0
ENDSEC
0
EOF
''';
    _viewModel.loadDxf(sampleDxf, productType: 'Formed Z-Bracket');
  }
}
