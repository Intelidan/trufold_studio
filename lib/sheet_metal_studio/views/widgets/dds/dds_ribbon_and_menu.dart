// =============================================================================
// dds_ribbon_and_menu.dart
//
// Dedicated Desktop Window Title Bar, Menu Bar, and Ribbon Toolbar for
// TruFold TDS Studio (Technical Data Sheet & Client Submittal Suite).
//
// Provides full standalone app window capabilities:
// 1. DdsWindowTitleBar: OS-style draggable window frame with Minimize, Maximize/Restore, Close
// 2. DdsMenuBar: Dedicated MenuBar (File, Edit, Library, Document, Order, View, CAD Link)
// 3. DdsRibbonToolbar: Grouped action ribbon (Doc Control, Add from Library, Order Level, 3D Dimensions, CAD Link)
// =============================================================================

import 'package:flutter/material.dart';
import '../../../models/dds/dds_document.dart';
import '../../../models/dds/dds_product_instance.dart';
import '../../../engine/dds/dds_instance_evaluator.dart';

class DdsWindowTitleBar extends StatelessWidget {
  final DdsDocument document;
  final bool isMaximized;
  final bool isWindowMode;
  final VoidCallback? onMinimize;
  final VoidCallback? onToggleMaximize;
  final VoidCallback? onDockSplit;
  final VoidCallback? onClose;
  final GestureDragStartCallback? onDragStart;
  final GestureDragUpdateCallback? onDragUpdate;

  const DdsWindowTitleBar({
    super.key,
    required this.document,
    this.isMaximized = true,
    this.isWindowMode = true,
    this.onMinimize,
    this.onToggleMaximize,
    this.onDockSplit,
    this.onClose,
    this.onDragStart,
    this.onDragUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final proj = document.projectInfo;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: onDragStart,
      onPanUpdate: onDragUpdate,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 10.0),
        decoration: const BoxDecoration(
          color: Color(0xFF090E17),
          border: Border(
            bottom: BorderSide(color: Color(0xFF1E293B), width: 1.0),
          ),
        ),
        child: Row(
          children: [
            // App Badge / Icon
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7.0, vertical: 2.5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
                ),
                borderRadius: BorderRadius.circular(4.0),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.picture_as_pdf, size: 12, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'TDS STUDIO',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10.0,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // Window Title & Document ID
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      proj.documentTitle.isNotEmpty ? proj.documentTitle : 'Technical Data Sheet & Submittal Suite',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(3.0),
                      border: Border.all(color: const Color(0xFF334155), width: 0.8),
                    ),
                    child: Text(
                      '${proj.documentNumber} • REV ${proj.revision}',
                      style: const TextStyle(
                        color: Color(0xFF38BDF8),
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (proj.client.isNotEmpty)
                    Text(
                      '(${proj.client})',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 10.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),

            // Window Controls (Minimize, Maximize/Restore, Dock, Close)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onDockSplit != null)
                  _buildWindowBtn(
                    icon: Icons.vertical_split,
                    tooltip: 'Dock Split Screen with CAD',
                    onTap: onDockSplit,
                  ),
                if (onMinimize != null)
                  _buildWindowBtn(
                    icon: Icons.remove,
                    tooltip: 'Minimize TDS Window',
                    onTap: onMinimize,
                  ),
                if (onToggleMaximize != null)
                  _buildWindowBtn(
                    icon: isMaximized ? Icons.filter_none : Icons.crop_square,
                    tooltip: isMaximized ? 'Restore Floating Window' : 'Maximize Window',
                    onTap: onToggleMaximize,
                  ),
                if (onClose != null)
                  _buildWindowBtn(
                    icon: Icons.close,
                    tooltip: 'Close TDS Window',
                    isClose: true,
                    onTap: onClose,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWindowBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    bool isClose = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        hoverColor: isClose ? const Color(0xFFE11D48) : Colors.white12,
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          width: 32,
          height: 28,
          child: Center(
            child: Icon(
              icon,
              size: 14,
              color: isClose ? const Color(0xFFCBD5E1) : const Color(0xFF94A3B8),
            ),
          ),
        ),
      ),
    );
  }
}

class DdsMenuBarWidget extends StatelessWidget {
  final DdsDocument document;
  final VoidCallback onNewDocument;
  final VoidCallback onOpenDocument;
  final VoidCallback onSaveDocument;
  final VoidCallback? onSaveAsDocument;
  final VoidCallback? onExportPdf;
  final VoidCallback? onExportDxf;
  final VoidCallback? onImportExcel;
  final VoidCallback? onAddProductSheet;
  final VoidCallback? onAddCoverSheet;
  final VoidCallback? onDuplicateSheet;
  final VoidCallback? onDeleteSheet;
  final VoidCallback? onOpenLibrary;
  final VoidCallback? onEditInMainCad;
  final VoidCallback? onSyncFromCad;
  final VoidCallback? onToggleProperties;
  final VoidCallback? onToggleCmsInspector;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback? onClose;

  const DdsMenuBarWidget({
    super.key,
    required this.document,
    required this.onNewDocument,
    required this.onOpenDocument,
    required this.onSaveDocument,
    this.onSaveAsDocument,
    this.onExportPdf,
    this.onExportDxf,
    this.onImportExcel,
    this.onAddProductSheet,
    this.onAddCoverSheet,
    this.onDuplicateSheet,
    this.onDeleteSheet,
    this.onOpenLibrary,
    this.onEditInMainCad,
    this.onSyncFromCad,
    this.onToggleProperties,
    this.onToggleCmsInspector,
    this.onUndo,
    this.onRedo,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(
          bottom: BorderSide(color: Color(0xFF1E293B), width: 1.0),
        ),
      ),
      child: Row(
        children: [
          _buildMenuDropdown(
            context,
            title: 'File',
            items: [
              _MenuItem('New TDS Document', Icons.note_add_outlined, 'Ctrl+N', onNewDocument),
              _MenuItem('Open .dds Submittal...', Icons.file_open_outlined, 'Ctrl+O', onOpenDocument),
              _MenuItem('Save .dds', Icons.save_outlined, 'Ctrl+S', onSaveDocument),
              if (onSaveAsDocument != null)
                _MenuItem('Save As...', Icons.save_as_outlined, '', onSaveAsDocument!),
              const _MenuDivider(),
              if (onExportPdf != null)
                _MenuItem('Export PDF Submittal (A4/A3)', Icons.picture_as_pdf, 'Ctrl+P', onExportPdf!),
              if (onExportDxf != null)
                _MenuItem('Export DXF Manufacturing Sheet', Icons.architecture, '', onExportDxf!),
              if (onImportExcel != null)
                _MenuItem('Import Excel Order Schedule (.xlsx)', Icons.table_chart, '', onImportExcel!),
              const _MenuDivider(),
              if (onClose != null)
                _MenuItem('Close TDS Window', Icons.close, 'Alt+F4', onClose!),
            ],
          ),
          _buildMenuDropdown(
            context,
            title: 'Edit',
            items: [
              _MenuItem('Undo', Icons.undo, 'Ctrl+Z', onUndo ?? () {}),
              _MenuItem('Redo', Icons.redo, 'Ctrl+Y', onRedo ?? () {}),
              const _MenuDivider(),
              _MenuItem('Clear All Sheet Markup', Icons.clear_all, '', () {}),
              _MenuItem('Reset 3D Dimension Callouts', Icons.refresh, '', () {}),
            ],
          ),
          _buildMenuDropdown(
            context,
            title: 'Library',
            items: [
              if (onOpenLibrary != null)
                _MenuItem('Browse CMS Fitting Library...', Icons.collections_bookmark, '', onOpenLibrary!),
              const _MenuDivider(),
              _MenuItem('Cable Trunking Reducers (Concentric / Eccentric)', Icons.call_split, '', () => onOpenLibrary?.call()),
              _MenuItem('Equal & Unequal Tees (90° Branch)', Icons.alt_route, '', () => onOpenLibrary?.call()),
              _MenuItem('Cross Fittings (4-Way Intersection)', Icons.close, '', () => onOpenLibrary?.call()),
              _MenuItem('Horizontal & Vertical Bends (90° / 45°)', Icons.turn_sharp_right, '', () => onOpenLibrary?.call()),
              _MenuItem('Straight Cable Trays & Accessories', Icons.view_column, '', () => onOpenLibrary?.call()),
              const _MenuDivider(),
              if (onImportExcel != null)
                _MenuItem('Batch Import Fittings from Excel BOM', Icons.table_rows, '', onImportExcel!),
            ],
          ),
          _buildMenuDropdown(
            context,
            title: 'Document',
            items: [
              if (onAddProductSheet != null)
                _MenuItem('Add New Part Sheet', Icons.add_to_photos_outlined, '', onAddProductSheet!),
              if (onAddCoverSheet != null)
                _MenuItem('Add Cover Schedule Sheet', Icons.featured_play_list_outlined, '', onAddCoverSheet!),
              if (onDuplicateSheet != null)
                _MenuItem('Duplicate Active Sheet', Icons.copy, '', onDuplicateSheet!),
              if (onDeleteSheet != null)
                _MenuItem('Delete Active Sheet', Icons.delete_outline, '', onDeleteSheet!),
              const _MenuDivider(),
              _MenuItem('Sheet Title Block Setup (ISO 7200)', Icons.view_headline, '', () => onToggleProperties?.call()),
              _MenuItem('Engineering Sign-Offs (Prepared / Checked / Approved)', Icons.verified, '', () => onToggleProperties?.call()),
            ],
          ),
          _buildMenuDropdown(
            context,
            title: 'Order',
            items: [
              _MenuItem('Purchase Order (PO) Details', Icons.receipt_long, '', () => onToggleProperties?.call()),
              _MenuItem('Client Reference & Tagging', Icons.tag, '', () => onToggleProperties?.call()),
              _MenuItem('Batch Quantity & Item Lines', Icons.numbers, '', () => onToggleProperties?.call()),
              _MenuItem('Material Specification (Pre-Galv DX51D / SS316)', Icons.layers, '', () => onToggleProperties?.call()),
              _MenuItem('Takeoff Calculation (Net Mass & Blank Area)', Icons.scale, '', () => onToggleProperties?.call()),
            ],
          ),
          _buildMenuDropdown(
            context,
            title: 'View',
            items: [
              _MenuItem('3D Client Presentation View', Icons.view_in_ar, '', () {}),
              if (onToggleCmsInspector != null)
                _MenuItem('Floating Parameters Inspector', Icons.tune, 'F6', onToggleCmsInspector!),
              _MenuItem('Toggle 3D Dimension Callouts', Icons.straighten, '', () {}),
              _MenuItem('Toggle 45° Section Hatching', Icons.texture, '', () {}),
              _MenuItem('Reset 3D Camera Orbit & Zoom', Icons.center_focus_strong, '', () {}),
            ],
          ),
          _buildMenuDropdown(
            context,
            title: 'CAD Link',
            items: [
              if (onEditInMainCad != null)
                _MenuItem('Edit Active Part in Main CAD Window', Icons.open_in_browser, 'Live Link', onEditInMainCad!),
              if (onSyncFromCad != null)
                _MenuItem('Sync Active Part from Main CAD Tab', Icons.sync, '', onSyncFromCad!),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMenuDropdown(
    BuildContext context, {
    required String title,
    required List<dynamic> items,
  }) {
    return PopupMenuButton<VoidCallback>(
      tooltip: '',
      offset: const Offset(0, 24),
      color: const Color(0xFF0F172A),
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: Color(0xFF334155), width: 1.0),
      ),
      onSelected: (action) => action(),
      itemBuilder: (ctx) => items.map<PopupMenuEntry<VoidCallback>>((item) {
        if (item is _MenuDivider) {
          return const PopupMenuDivider(height: 1);
        }
        final mi = item as _MenuItem;
        return PopupMenuItem<VoidCallback>(
          value: mi.action,
          height: 30,
          child: Row(
            children: [
              Icon(mi.icon, size: 14, color: const Color(0xFF38BDF8)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  mi.label,
                  style: const TextStyle(fontSize: 11.5, color: Colors.white, fontWeight: FontWeight.w500),
                ),
              ),
              if (mi.shortcut.isNotEmpty)
                Text(
                  mi.shortcut,
                  style: const TextStyle(fontSize: 9.5, color: Color(0xFF64748B), fontWeight: FontWeight.bold),
                ),
            ],
          ),
        );
      }).toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: Text(
          title,
          style: const TextStyle(
            color: Color(0xFFCBD5E1),
            fontSize: 12.0,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class DdsRibbonToolbarWidget extends StatelessWidget {
  final DdsDocument document;
  final DdsProductInstance? activeInstance;
  final EvaluatedDdsInstance? evaluatedInstance;
  final VoidCallback onNewDoc;
  final VoidCallback onOpenDoc;
  final VoidCallback onSaveDoc;
  final VoidCallback onExportPdf;
  final VoidCallback onOpenLibrary;
  final VoidCallback onImportExcel;
  final VoidCallback? onAddSheet;
  final VoidCallback onEditInMainCad;
  final VoidCallback onSyncFromCad;
  final VoidCallback? onToggleProperties;
  final VoidCallback? onToggleCmsInspector;
  final bool isPropertiesOpen;
  final bool isCmsInspectorOpen;

  // 3D Dimension toggle callbacks (retained for backward compatibility, now page-specific)
  final bool showDimWidth;
  final bool showDimHeight;
  final bool showDimPorts;
  final bool showDimSlots;
  final bool showDimFlange;
  final bool showDimGauge;
  final ValueChanged<String>? onToggleDimension;
  final VoidCallback? onToggleAllDimensions;

  const DdsRibbonToolbarWidget({
    super.key,
    required this.document,
    this.activeInstance,
    this.evaluatedInstance,
    required this.onNewDoc,
    required this.onOpenDoc,
    required this.onSaveDoc,
    required this.onExportPdf,
    required this.onOpenLibrary,
    required this.onImportExcel,
    this.onAddSheet,
    required this.onEditInMainCad,
    required this.onSyncFromCad,
    required this.onToggleProperties,
    this.onToggleCmsInspector,
    this.isPropertiesOpen = true,
    this.isCmsInspectorOpen = false,
    this.showDimWidth = true,
    this.showDimHeight = true,
    this.showDimPorts = true,
    this.showDimSlots = true,
    this.showDimFlange = true,
    this.showDimGauge = true,
    this.onToggleDimension,
    this.onToggleAllDimensions,
  });

  @override
  Widget build(BuildContext context) {
    final takeoff = evaluatedInstance?.calculatedTakeoff ?? activeInstance?.calculatedTakeoff;
    final orderLine = activeInstance?.orderLine;
    final qty = orderLine?.quantity ?? 1;
    final mass = takeoff != null ? '${takeoff.estimatedNetWeightKg.toStringAsFixed(2)} kg' : '1.45 kg';
    final area = takeoff != null ? '${takeoff.blankSurfaceAreaM2.toStringAsFixed(3)} m²' : '0.185 m²';

    return Container(
      width: double.infinity,
      height: 66,
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(
          bottom: BorderSide(color: Color(0xFF1E293B), width: 1.2),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // =================================================================
            // Group 1: Document Control (Top Level)
            // =================================================================
            _buildRibbonGroup(
              title: 'DOC CONTROL',
              children: [
                _buildRibbonButton(
                  icon: Icons.note_add_outlined,
                  label: 'New',
                  onTap: onNewDoc,
                ),
                _buildRibbonButton(
                  icon: Icons.file_open_outlined,
                  label: 'Open',
                  onTap: onOpenDoc,
                ),
                _buildRibbonButton(
                  icon: Icons.save_outlined,
                  label: 'Save',
                  accentColor: const Color(0xFF0284C7),
                  onTap: onSaveDoc,
                ),
                _buildRibbonButton(
                  icon: Icons.picture_as_pdf,
                  label: 'PDF Submittal',
                  accentColor: const Color(0xFFE11D48),
                  onTap: onExportPdf,
                ),
              ],
            ),
            const VerticalDivider(width: 14, thickness: 1.0, color: Color(0xFF1E293B)),

            // =================================================================
            // Group 2: Library & Part Insertion
            // =================================================================
            _buildRibbonGroup(
              title: 'SHEETS & IMPORT',
              children: [
                _buildRibbonButton(
                  icon: Icons.table_chart,
                  label: 'Excel Import',
                  accentColor: const Color(0xFF10B981),
                  onTap: onImportExcel,
                ),
                if (onAddSheet != null)
                  _buildRibbonButton(
                    icon: Icons.add_to_photos_outlined,
                    label: 'Add Sheet',
                    onTap: onAddSheet,
                  ),
              ],
            ),
            const VerticalDivider(width: 14, thickness: 1.0, color: Color(0xFF1E293B)),

            // =================================================================
            // Group 3: Order Level & Traceability
            // =================================================================
            _buildRibbonGroup(
              title: 'ORDER & TAKEOFF',
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: const Color(0xFF334155), width: 0.8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.receipt_long, size: 12, color: Color(0xFF38BDF8)),
                          const SizedBox(width: 4),
                          Text(
                            'PO: ${orderLine?.orderNumber.isNotEmpty == true ? orderLine!.orderNumber : "PO-88210"} (Line ${orderLine?.lineNumber ?? "001"})',
                            style: const TextStyle(fontSize: 10.0, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Qty: $qty pcs  |  Net: $mass  |  Area: $area',
                        style: const TextStyle(fontSize: 9.0, color: Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const VerticalDivider(width: 14, thickness: 1.0, color: Color(0xFF1E293B)),

            // =================================================================
            // Group 4: CAD Link Level
            // =================================================================
            _buildRibbonGroup(
              title: 'CAD LINK & SYNC',
              children: [
                _buildLargeActionCard(
                  icon: Icons.open_in_browser,
                  title: 'Edit in Main CAD',
                  subtitle: 'Opens new linked tab',
                  gradient: const [Color(0xFF4F46E5), Color(0xFF4338CA)],
                  onTap: onEditInMainCad,
                ),
                const SizedBox(width: 6),
                _buildRibbonButton(
                  icon: Icons.sync,
                  label: 'Sync from CAD',
                  accentColor: const Color(0xFF818CF8),
                  onTap: onSyncFromCad,
                ),
              ],
            ),
            const VerticalDivider(width: 14, thickness: 1.0, color: Color(0xFF1E293B)),

            // =================================================================
            // Group 6: Properties Box & Parameters Inspector
            // =================================================================
            _buildRibbonGroup(
              title: 'PROPERTIES',
              children: [
                _buildRibbonButton(
                  icon: isPropertiesOpen ? Icons.dock : Icons.dock_outlined,
                  label: 'Inspector Box',
                  accentColor: isPropertiesOpen ? const Color(0xFF0284C7) : const Color(0xFF94A3B8),
                  onTap: onToggleProperties,
                ),
                if (onToggleCmsInspector != null) ...[
                  const SizedBox(width: 4),
                  _buildRibbonButton(
                    icon: Icons.tune,
                    label: 'Param Inspector',
                    accentColor: isCmsInspectorOpen ? const Color(0xFF0284C7) : const Color(0xFF94A3B8),
                    onTap: onToggleCmsInspector,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRibbonGroup({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: children,
        ),
        const SizedBox(height: 3),
        Text(
          title,
          style: const TextStyle(
            fontSize: 9.0,
            fontWeight: FontWeight.w600,
            color: Color(0xFF64748B),
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }

  Widget _buildRibbonButton({
    required IconData icon,
    required String label,
    Color accentColor = const Color(0xFF94A3B8),
    VoidCallback? onTap,
  }) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        hoverColor: Colors.white12,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: accentColor),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(fontSize: 10.5, color: Color(0xFFCBD5E1), fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLargeActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradient),
          borderRadius: BorderRadius.circular(5),
          boxShadow: [
            BoxShadow(color: gradient.first.withValues(alpha: 0.35), blurRadius: 4, offset: const Offset(0, 1)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 11.0, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 8.5, color: Colors.white70),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuItem {
  final String label;
  final IconData icon;
  final String shortcut;
  final VoidCallback action;

  const _MenuItem(this.label, this.icon, this.shortcut, this.action);
}

class _MenuDivider {
  const _MenuDivider();
}
