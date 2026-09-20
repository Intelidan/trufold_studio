// =============================================================================
// CanvasDimensionEditorMixin
//
// Provides in-place dimension value editing state + logic for
// _UnfoldedCanvasWidgetState. Extracted from unfolded_canvas_widget.dart.
// =============================================================================

part of '../unfolded_canvas_widget.dart';

/// Mixin that contributes in-place dimension editing state and methods to
/// [_UnfoldedCanvasWidgetState].
mixin CanvasDimensionEditorMixin on State<UnfoldedCanvasWidget> {
  // ---------------------------------------------------------------------------
  // In-Place Dimension Value Editor State
  // ---------------------------------------------------------------------------
  String? _editingDimId;
  Rect? _editingDimRect;
  CadPoint2D? _activeInlineDimPA;
  CadPoint2D? _activeInlineDimPB;
  String? _activeInlineDimRefA;
  String? _activeInlineDimRefB;
  double _activeInlineDimOffset = 25.0;

  final TextEditingController _inPlaceDimController = TextEditingController();
  final FocusNode _inPlaceDimFocusNode = FocusNode();

  final Map<String, Rect> _dimensionBadgeRects = {};
  @visibleForTesting
  Map<String, Rect> get dimensionBadgeRects => _dimensionBadgeRects;

  final Map<String, double> _dimensionBadgeValues = {};

  final Map<
    String,
    ({
      Offset pA,
      Offset pB,
      double offsetDist,
      CadPoint2D ptA,
      CadPoint2D ptB,
      CadDimensionType type,
    })
  >
  _dimensionLineSegments = {};

  String? _hoveredDimId;
  String? _hoveredDimLineId;
  String? _draggedDimLineId;
  String? _draggedDimId;
  Offset _dragDimensionStartOffset = Offset.zero;

  // ---------------------------------------------------------------------------
  // Lifecycle hooks — called by _UnfoldedCanvasWidgetState
  // ---------------------------------------------------------------------------

  void _initDimensionEditorMixin() {
    _inPlaceDimFocusNode.addListener(() {
      if (!_inPlaceDimFocusNode.hasFocus && _editingDimId != null) {
        _commitInPlaceDimensionEdit(widget.viewModel);
      }
    });
  }

  void _disposeDimensionEditorMixin() {
    _inPlaceDimController.dispose();
    _inPlaceDimFocusNode.dispose();
  }

  // ---------------------------------------------------------------------------
  // In-Place Dimension Edit Logic
  // ---------------------------------------------------------------------------

  void _startInPlaceDimensionEdit({
    required String dimId,
    required Rect badgeRect,
    required double initialValue,
    CadPoint2D? pA,
    CadPoint2D? pB,
    String? referenceAId,
    String? referenceBId,
    double offset = 25.0,
  }) {
    setState(() {
      _editingDimId = dimId;
      _editingDimRect = badgeRect;
      _activeInlineDimPA = pA;
      _activeInlineDimPB = pB;
      _activeInlineDimRefA = referenceAId;
      _activeInlineDimRefB = referenceBId;
      _activeInlineDimOffset = offset;
      _inPlaceDimController.text = initialValue > 0
          ? initialValue.toStringAsFixed(2)
          : '';
      _inPlaceDimController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _inPlaceDimController.text.length,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inPlaceDimFocusNode.requestFocus();
    });
  }

  @visibleForTesting
  void startInPlaceDimensionEditForTesting(String dimId) {
    final rect =
        _dimensionBadgeRects[dimId] ?? const Rect.fromLTWH(100, 100, 60, 22);
    final currentValue =
        _dimensionBadgeValues[dimId] ??
        (dimId == 'dim_blank_w'
            ? widget.viewModel.document.blankWidthMm
            : widget.viewModel.document.blankLengthMm);
    _startInPlaceDimensionEdit(
      dimId: dimId,
      badgeRect: rect,
      initialValue: currentValue,
    );
  }

  void _cancelInPlaceDimensionEdit() {
    setState(() {
      _editingDimId = null;
      _editingDimRect = null;
      _activeInlineDimPA = null;
      _activeInlineDimPB = null;
      _activeInlineDimRefA = null;
      _activeInlineDimRefB = null;
    });
  }

  void _commitInPlaceDimensionEdit(SheetMetalStudioViewModel viewModel) {
    if (_editingDimId == null) return;
    final text = _inPlaceDimController.text.trim();
    final parsed = double.tryParse(text);
    if (parsed != null && parsed > 0) {
      final dimId = _editingDimId!;
      final existingDim = viewModel.document.dimensions
          .where((d) => d.id == dimId)
          .firstOrNull;
      if (existingDim != null ||
          dimId == 'dim_blank_w' ||
          dimId == 'dim_blank_l') {
        viewModel.driveDimension(dimId, parsed);
      } else if (_activeInlineDimPA != null && _activeInlineDimPB != null) {
        viewModel.commitInteractiveDimension(
          pA: _activeInlineDimPA!,
          pB: _activeInlineDimPB!,
          referenceAId: _activeInlineDimRefA,
          referenceBId: _activeInlineDimRefB,
          offset: _activeInlineDimOffset,
          customValue: parsed,
        );
      } else {
        viewModel.driveDimension(dimId, parsed);
      }
    }
    _cancelInPlaceDimensionEdit();
  }

  // ---------------------------------------------------------------------------
  // In-Place Dimension Editor Widget
  // ---------------------------------------------------------------------------

  Widget _buildInPlaceDimensionEditor(SheetMetalStudioViewModel viewModel) {
    if (_editingDimId == null) return const SizedBox.shrink();

    final currentRect = _dimensionBadgeRects[_editingDimId] ?? _editingDimRect;
    if (currentRect == null) return const SizedBox.shrink();

    final center = currentRect.center;
    final width = (currentRect.width + 24.0).clamp(76.0, 400.0);
    const height = 24.0;

    return Positioned(
      left: (center.dx - width / 2.0).clamp(4.0, 4000.0),
      top: (center.dy - height / 2.0).clamp(4.0, 4000.0),
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.escape) {
              _cancelInPlaceDimensionEdit();
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                event.logicalKey == LogicalKeyboardKey.tab) {
              _commitInPlaceDimensionEdit(viewModel);
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(3.5),
            border: Border.all(color: const Color(0xFF0284C7), width: 1.6),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0284C7).withValues(alpha: 0.25),
                blurRadius: 5,
                spreadRadius: 1,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 4,
                offset: const Offset(0, 1.5),
              ),
            ],
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: TextField(
            controller: _inPlaceDimController,
            focusNode: _inPlaceDimFocusNode,
            autofocus: true,
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 11.0,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              letterSpacing: 0.2,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            onSubmitted: (_) => _commitInPlaceDimensionEdit(viewModel),
          ),
        ),
      ),
    );
  }
}
