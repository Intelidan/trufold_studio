// =============================================================================
// cad_property_inspector.dart
//
// Context-Sensitive Properties Inspector per Master Guide Step 5 (#18).
// Unifies property inspection and editing for:
// - Line / Cut Segment (endpoints, length, angle, layer)
// - Punch / Slot (type, center, diameter, length/width, rotation)
// - Fold Bend Line (direction, angle, radius, K-factor, constraints)
// - Perforation Pattern (rows, cols, pitch, stagger, dimensions)
// - Planar Face (label, role, anchor, area, holes)
// - Associative Dimension (type, value, driving status, tolerances)
// - Multi-Entity Batch Inspector (homogeneous & heterogeneous selections)
// - Part & Sheet Metal Document Properties (fallback when nothing selected)
// =============================================================================

import 'package:flutter/material.dart';
import '../../viewmodels/sheet_metal_studio_viewmodel.dart';
import 'bend_property_sheet.dart';
import 'punch_property_sheet.dart';
import 'pattern_property_sheet.dart';
import 'face_property_sheet.dart';
import 'line_property_sheet.dart';
import 'arc_property_sheet.dart';
import 'dimension_property_sheet.dart';
import 'active_tool_property_sheet.dart';
import 'template_parameter_sheet.dart';

class CadPropertyInspector extends StatelessWidget {
  final SheetMetalStudioViewModel viewModel;
  final bool isCollapsed;
  final VoidCallback? onToggleCollapse;
  final VoidCallback? onClose;
  final GestureDragStartCallback? onDragStartHeader;
  final GestureDragUpdateCallback? onDragHeader;

  const CadPropertyInspector({
    super.key,
    required this.viewModel,
    this.isCollapsed = false,
    this.onToggleCollapse,
    this.onClose,
    this.onDragStartHeader,
    this.onDragHeader,
  });

  @override
  Widget build(BuildContext context) {
    // 0. Active Parametric Template Mode
    if (viewModel.isTemplateActive && viewModel.activeTemplate != null) {
      return TemplateParameterSheet(
        viewModel: viewModel,
        template: viewModel.activeTemplate!,
        isCollapsed: isCollapsed,
        onToggleCollapse: onToggleCollapse,
        onClose: () => viewModel.closeTemplateMode(),
        onDragStartHeader: onDragStartHeader,
        onDragHeader: onDragHeader,
      );
    }

    // Multi-Selection of parts (homogeneous or heterogeneous)
    final selectedIds = viewModel.selectedEntityIds;
    if (selectedIds.length > 1) {
      // 1. Multiple punches/holes
      final punches = viewModel.document.allPunchesRaw
          .where((p) => selectedIds.contains(p.id))
          .toList();
      if (punches.isNotEmpty && punches.length == selectedIds.length) {
        return PunchPropertySheet(
          viewModel: viewModel,
          punch: punches.first,
          punches: punches,
          isCollapsed: isCollapsed,
          onToggleCollapse: onToggleCollapse,
          onClose: onClose,
          onDragStartHeader: onDragStartHeader,
          onDragHeader: onDragHeader,
        );
      }

      // 2. Multiple bends
      final bends = viewModel.document.bends
          .where((b) => selectedIds.contains(b.id))
          .toList();
      if (bends.isNotEmpty && bends.length == selectedIds.length) {
        return BendPropertySheet(
          viewModel: viewModel,
          bend: bends.first,
          isCollapsed: isCollapsed,
          onToggleCollapse: onToggleCollapse,
          onClose: onClose,
          onDragStartHeader: onDragStartHeader,
          onDragHeader: onDragHeader,
        );
      }

      // 3. Multiple cut lines
      final cuts = viewModel.document.cutLines
          .where((c) => selectedIds.contains(c.id))
          .toList();
      if (cuts.isNotEmpty && cuts.length == selectedIds.length) {
        return LinePropertySheet(
          viewModel: viewModel,
          line: cuts.first,
          isCollapsed: isCollapsed,
          onToggleCollapse: onToggleCollapse,
          onClose: onClose,
          onDragStartHeader: onDragStartHeader,
          onDragHeader: onDragHeader,
        );
      }

      // 4. Multiple arcs
      final arcs = viewModel.document.arcs
          .where((a) => selectedIds.contains(a.id))
          .toList();
      if (arcs.isNotEmpty && arcs.length == selectedIds.length) {
        return ArcPropertySheet(
          viewModel: viewModel,
          arc: arcs.first,
          isCollapsed: isCollapsed,
          onToggleCollapse: onToggleCollapse,
          onClose: onClose,
          onDragStartHeader: onDragStartHeader,
          onDragHeader: onDragHeader,
        );
      }

      // 5. Multiple perforation patterns
      final patterns = viewModel.document.perforationPatterns
          .where((pat) => selectedIds.contains(pat.id))
          .toList();
      if (patterns.isNotEmpty && patterns.length == selectedIds.length) {
        return PatternPropertySheet(
          viewModel: viewModel,
          pattern: patterns.first,
          selectedHoleIndex: null,
          isCollapsed: isCollapsed,
          onToggleCollapse: onToggleCollapse,
          onClose: onClose,
          onDragStartHeader: onDragStartHeader,
          onDragHeader: onDragHeader,
        );
      }

      // 6. Heterogeneous Multi-Selection
      return _MultiEntityPropertySheet(
        viewModel: viewModel,
        selectedIds: selectedIds,
        isCollapsed: isCollapsed,
        onToggleCollapse: onToggleCollapse,
        onClose: onClose,
        onDragStartHeader: onDragStartHeader,
        onDragHeader: onDragHeader,
      );
    }

    // 1. Single Punch selected
    if (viewModel.selectedPunchId != null) {
      final punch = viewModel.document.allPunchesRaw
          .where((p) => p.id == viewModel.selectedPunchId)
          .firstOrNull;
      if (punch != null) {
        return PunchPropertySheet(
          viewModel: viewModel,
          punch: punch,
          punches: [punch],
          isCollapsed: isCollapsed,
          onToggleCollapse: onToggleCollapse,
          onClose: onClose,
          onDragStartHeader: onDragStartHeader,
          onDragHeader: onDragHeader,
        );
      }
    }

    // 2. Single Line / Cut selected
    if (viewModel.selectedCutId != null) {
      final cut = viewModel.document.cutLines
          .where((c) => c.id == viewModel.selectedCutId)
          .firstOrNull;
      if (cut != null) {
        return LinePropertySheet(
          viewModel: viewModel,
          line: cut,
          isCollapsed: isCollapsed,
          onToggleCollapse: onToggleCollapse,
          onClose: onClose,
          onDragStartHeader: onDragStartHeader,
          onDragHeader: onDragHeader,
        );
      }
    }

    // 2b. Single Arc selected
    if (viewModel.selectedArcId != null) {
      final arc = viewModel.document.arcs
          .where((a) => a.id == viewModel.selectedArcId)
          .firstOrNull;
      if (arc != null) {
        return ArcPropertySheet(
          viewModel: viewModel,
          arc: arc,
          isCollapsed: isCollapsed,
          onToggleCollapse: onToggleCollapse,
          onClose: onClose,
          onDragStartHeader: onDragStartHeader,
          onDragHeader: onDragHeader,
        );
      }
    }

    // 3. Single Bend selected
    if (viewModel.selectedBendId != null) {
      final bend = viewModel.document.bends
          .where((b) => b.id == viewModel.selectedBendId)
          .firstOrNull;
      if (bend != null) {
        return BendPropertySheet(
          viewModel: viewModel,
          bend: bend,
          isCollapsed: isCollapsed,
          onToggleCollapse: onToggleCollapse,
          onClose: onClose,
          onDragStartHeader: onDragStartHeader,
          onDragHeader: onDragHeader,
        );
      }
    }

    // 4. Single Pattern selected
    if (viewModel.selectedPatternId != null) {
      final pattern = viewModel.document.perforationPatterns
          .where((p) => p.id == viewModel.selectedPatternId)
          .firstOrNull;
      if (pattern != null) {
        return PatternPropertySheet(
          viewModel: viewModel,
          pattern: pattern,
          selectedHoleIndex: viewModel.selectedPatternHoleIndex,
          isCollapsed: isCollapsed,
          onToggleCollapse: onToggleCollapse,
          onClose: onClose,
          onDragStartHeader: onDragStartHeader,
          onDragHeader: onDragHeader,
        );
      }
    }

    // 5. Single Face selected
    if (viewModel.selectedFaceId != null) {
      final face = viewModel.document.faces
          .where((f) => f.id == viewModel.selectedFaceId)
          .firstOrNull;
      if (face != null) {
        return FacePropertySheet(
          viewModel: viewModel,
          face: face,
          isCollapsed: isCollapsed,
          onToggleCollapse: onToggleCollapse,
          onClose: onClose,
          onDragStartHeader: onDragStartHeader,
          onDragHeader: onDragHeader,
        );
      }
    }

    // 6. Single Dimension selected
    if (viewModel.selectedDimensionId != null) {
      final dim = viewModel.document.dimensions
          .where((d) => d.id == viewModel.selectedDimensionId)
          .firstOrNull;
      if (dim != null) {
        return DimensionPropertySheet(
          viewModel: viewModel,
          dimension: dim,
          isCollapsed: isCollapsed,
          onToggleCollapse: onToggleCollapse,
          onClose: onClose,
          onDragStartHeader: onDragStartHeader,
          onDragHeader: onDragHeader,
        );
      }
    }

    // 7. Active Tool Config fallback if in a creation tool mode
    if (viewModel.toolMode != StudioToolMode.select) {
      return ActiveToolPropertySheet(
        viewModel: viewModel,
        onClose: onClose,
        onDragStartHeader: onDragStartHeader,
        onDragHeader: onDragHeader,
      );
    }

    // 8. Document & Sheet Properties (when properties panel is opened with no selection)
    return _DocumentPropertySheet(
      viewModel: viewModel,
      isCollapsed: isCollapsed,
      onToggleCollapse: onToggleCollapse,
      onClose: onClose,
      onDragStartHeader: onDragStartHeader,
      onDragHeader: onDragHeader,
    );
  }
}

// =============================================================================
// Heterogeneous Multi-Selection Property Sheet
// =============================================================================
class _MultiEntityPropertySheet extends StatelessWidget {
  final SheetMetalStudioViewModel viewModel;
  final Set<String> selectedIds;
  final bool isCollapsed;
  final VoidCallback? onToggleCollapse;
  final VoidCallback? onClose;
  final GestureDragStartCallback? onDragStartHeader;
  final GestureDragUpdateCallback? onDragHeader;

  const _MultiEntityPropertySheet({
    required this.viewModel,
    required this.selectedIds,
    this.isCollapsed = false,
    this.onToggleCollapse,
    this.onClose,
    this.onDragStartHeader,
    this.onDragHeader,
  });

  @override
  Widget build(BuildContext context) {
    const themeColor = Color(0xFF6366F1); // Indigo theme for multi-selection
    final doc = viewModel.document;

    final punchCount = doc.allPunchesRaw.where((p) => selectedIds.contains(p.id)).length;
    final bendCount = doc.bends.where((b) => selectedIds.contains(b.id)).length;
    final cutCount = doc.cutLines.where((c) => selectedIds.contains(c.id)).length;
    final arcCount = doc.arcs.where((a) => selectedIds.contains(a.id)).length;
    final patternCount = doc.perforationPatterns.where((p) => selectedIds.contains(p.id)).length;

    return GestureDetector(
      onPanStart: onDragStartHeader,
      onPanUpdate: onDragHeader,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 250.0,
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(color: themeColor.withValues(alpha: 0.5), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16.0,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.drag_indicator, size: 14, color: Color(0xFF94A3B8)),
                const SizedBox(width: 4),
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(color: themeColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${selectedIds.length} ITEMS SELECTED',
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (onToggleCollapse != null) ...[
                  InkWell(
                    onTap: onToggleCollapse,
                    child: Icon(
                      isCollapsed ? Icons.expand_more : Icons.expand_less,
                      size: 18,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                InkWell(
                  onTap: onClose ?? viewModel.clearSelection,
                  child: const Icon(Icons.close, size: 16, color: Color(0xFF64748B)),
                ),
              ],
            ),
            if (!isCollapsed) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(6.0),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (punchCount > 0)
                      _buildCountRow('Punches / Holes', punchCount, const Color(0xFF059669)),
                    if (bendCount > 0)
                      _buildCountRow('Press-Brake Bends', bendCount, const Color(0xFF0284C7)),
                    if (cutCount > 0)
                      _buildCountRow('Laser Cuts / Lines', cutCount, const Color(0xFFEA580C)),
                    if (arcCount > 0)
                      _buildCountRow('Arc Contours', arcCount, const Color(0xFF8B5CF6)),
                    if (patternCount > 0)
                      _buildCountRow('Perforation Patterns', patternCount, const Color(0xFF0D9488)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 6.0),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4.0)),
                      ),
                      onPressed: viewModel.clearSelection,
                      child: const Text('Deselect All', style: TextStyle(fontSize: 10.5)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 6.0),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4.0)),
                      ),
                      icon: const Icon(Icons.delete_outline, size: 13),
                      label: const Text('Delete', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                      onPressed: viewModel.deleteSelectedEntities,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCountRow(String label, int count, Color dotColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 10.5, color: Color(0xFF475569)),
            ),
          ),
          Text(
            '$count',
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Document & Blank Properties Sheet (Fallback when no entity is selected)
// =============================================================================
class _DocumentPropertySheet extends StatelessWidget {
  final SheetMetalStudioViewModel viewModel;
  final bool isCollapsed;
  final VoidCallback? onToggleCollapse;
  final VoidCallback? onClose;
  final GestureDragStartCallback? onDragStartHeader;
  final GestureDragUpdateCallback? onDragHeader;

  const _DocumentPropertySheet({
    required this.viewModel,
    this.isCollapsed = false,
    this.onToggleCollapse,
    this.onClose,
    this.onDragStartHeader,
    this.onDragHeader,
  });

  @override
  Widget build(BuildContext context) {
    const themeColor = Color(0xFF0284C7); // Cyan theme
    final doc = viewModel.document;

    return GestureDetector(
      onPanStart: onDragStartHeader,
      onPanUpdate: onDragHeader,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 250.0,
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(color: themeColor.withValues(alpha: 0.5), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16.0,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.drag_indicator, size: 14, color: Color(0xFF94A3B8)),
                const SizedBox(width: 4),
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(color: themeColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'DOCUMENT PROPERTIES',
                    style: TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (onToggleCollapse != null) ...[
                  InkWell(
                    onTap: onToggleCollapse,
                    child: Icon(
                      isCollapsed ? Icons.expand_more : Icons.expand_less,
                      size: 18,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                InkWell(
                  onTap: onClose ?? () => viewModel.setPropertyInspectorOpen(false),
                  child: const Icon(Icons.close, size: 16, color: Color(0xFF64748B)),
                ),
              ],
            ),
            if (!isCollapsed) ...[
              const SizedBox(height: 10),
              // Material & Gauge
              Container(
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(6.0),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildParamRow('Material', doc.material.materialType.shortCode),
                    _buildParamRow('Thickness', '${doc.material.thicknessMm.toStringAsFixed(2)} mm'),
                    _buildParamRow('K-Factor', doc.material.kFactor.toStringAsFixed(3)),
                    _buildParamRow('Bend Radius', '${doc.material.defaultBendRadius.toStringAsFixed(2)} mm'),
                    if (doc.blankWidthMm > 0 && doc.blankLengthMm > 0)
                      _buildParamRow(
                        'Blank Size',
                        '${doc.blankWidthMm.toStringAsFixed(0)} × ${doc.blankLengthMm.toStringAsFixed(0)} mm',
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // Elements Summary Badges
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  _buildCountBadge('Bends', doc.bends.length, const Color(0xFF0284C7)),
                  _buildCountBadge('Holes', doc.allPunchesRaw.length, const Color(0xFF059669)),
                  _buildCountBadge('Cuts', doc.cutLines.length, const Color(0xFFEA580C)),
                  if (doc.arcs.isNotEmpty)
                    _buildCountBadge('Arcs', doc.arcs.length, const Color(0xFF8B5CF6)),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.select_all, size: 13),
                  label: const Text('Select All Entities (Ctrl+A)', style: TextStyle(fontSize: 10.5)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 5.0),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4.0)),
                  ),
                  onPressed: viewModel.selectAll,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildParamRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B))),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountBadge(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        '$count $label',
        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}
