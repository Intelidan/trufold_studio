// =============================================================================
// studio_tab_model.dart
//
// Represents an open document tab in truFold Studio by Danish.
// Each tab maintains its own independent ViewModel instance, complete with:
// - Document geometry & parameters
// - 2D and 3D camera pan, zoom, and orbit orientation
// - Independent Undo / Redo history stacks
// - Independent selection and active tool states
// =============================================================================

import '../models/dsf_document.dart';
import '../viewmodels/sheet_metal_studio_viewmodel.dart';

class StudioTab {
  final String id;
  String title;
  String? filePath;
  final SheetMetalStudioViewModel viewModel;
  bool isModified;

  StudioTab({
    required this.id,
    required this.title,
    this.filePath,
    required this.viewModel,
    this.isModified = false,
  });

  factory StudioTab.fromDocument(
    DsfDocument doc, {
    String? title,
    String? filePath,
  }) {
    final t =
        title ?? (doc.itemName.isNotEmpty ? doc.itemName : 'Untitled Part');
    final vm = SheetMetalStudioViewModel(initialDocument: doc);
    return StudioTab(
      id: 'TAB_${DateTime.now().microsecondsSinceEpoch}',
      title: t,
      filePath: filePath,
      viewModel: vm,
    );
  }

  factory StudioTab.blank({String title = 'New Blank Part'}) {
    return StudioTab.fromDocument(
      DsfDocument.sampleCableTray(width: 100, height: 50, length: 300),
      title: title,
    );
  }

  void dispose() {
    viewModel.dispose();
  }
}
