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
// =============================================================================

import 'package:flutter/material.dart';
import '../../viewmodels/sheet_metal_studio_viewmodel.dart';
import 'bend_property_sheet.dart';
import 'punch_property_sheet.dart';
import 'pattern_property_sheet.dart';
import 'face_property_sheet.dart';
import 'line_property_sheet.dart';
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

    // 1. Dimension selected
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

    // 2. Line / Cut selected
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

    // 3. Bend selected
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

    // 4. Punch selected
    if (viewModel.selectedPunchId != null) {
      final punch = viewModel.document.allPunchesRaw
          .where((p) => p.id == viewModel.selectedPunchId)
          .firstOrNull;
      if (punch != null) {
        return PunchPropertySheet(
          viewModel: viewModel,
          punch: punch,
          isCollapsed: isCollapsed,
          onToggleCollapse: onToggleCollapse,
          onClose: onClose,
          onDragStartHeader: onDragStartHeader,
          onDragHeader: onDragHeader,
        );
      }
    }

    // 5. Pattern selected
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

    // 6. Face selected
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

    // 7. Active Tool Config fallback if in a creation tool mode
    if (viewModel.toolMode != StudioToolMode.select) {
      return ActiveToolPropertySheet(
        viewModel: viewModel,
        onClose: onClose,
        onDragStartHeader: onDragStartHeader,
        onDragHeader: onDragHeader,
      );
    }

    return const SizedBox.shrink();
  }
}
