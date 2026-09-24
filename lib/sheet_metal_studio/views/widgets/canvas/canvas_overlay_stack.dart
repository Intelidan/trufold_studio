// =============================================================================
// CanvasOverlayStackMixin
//
// Provides all floating canvas overlay widgets (fitting inspector badge,
// tool ribbon, floating property inspector, studio bottom bar, micro legend)
// for _UnfoldedCanvasWidgetState. Extracted from unfolded_canvas_widget.dart.
// =============================================================================

part of '../unfolded_canvas_widget.dart';

mixin CanvasOverlayStackMixin on State<UnfoldedCanvasWidget>, CanvasLegendMixin, CanvasDimensionEditorMixin, CanvasPortDimensionEditorMixin {
  // Draggable inspector panel offset (null defaults to top-right)
  Offset? _inspectorOffset;
  bool _isInspectorCollapsed = false;
  Offset? _dragStartGlobal;
  Offset? _dragStartPanel;

  // ---------------------------------------------------------------------------
  // Floating Property Inspector builder
  // ---------------------------------------------------------------------------
  Widget _buildFloatingInspector({
    required SheetMetalStudioViewModel viewModel,
    required Offset effectiveInspectorPos,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (details) {
        _dragStartGlobal = details.globalPosition;
        _dragStartPanel = effectiveInspectorPos;
      },
      onPanUpdate: (details) {
        if (_dragStartGlobal != null && _dragStartPanel != null) {
          setState(() {
            _inspectorOffset =
                _dragStartPanel! + (details.globalPosition - _dragStartGlobal!);
          });
        }
      },
      child: CadPropertyInspector(
        viewModel: viewModel,
        isCollapsed: _isInspectorCollapsed,
        onToggleCollapse: () {
          setState(() {
            _isInspectorCollapsed = !_isInspectorCollapsed;
          });
        },
        onClose: () {
          widget.viewModel.setPropertyInspectorOpen(false);
        },
        onDragStartHeader: (details) {
          _dragStartGlobal = details.globalPosition;
          _dragStartPanel = effectiveInspectorPos;
        },
        onDragHeader: (details) {
          if (_dragStartGlobal != null && _dragStartPanel != null) {
            setState(() {
              _inspectorOffset =
                  _dragStartPanel! +
                  (details.globalPosition - _dragStartGlobal!);
            });
          }
        },
      ),
    );
  }


  // ---------------------------------------------------------------------------
  // Overlay Stack Children
  // ---------------------------------------------------------------------------
  List<Widget> _buildOverlayStack({
    required BuildContext context,
    required SheetMetalStudioViewModel viewModel,
    required BoxConstraints constraints,
    required Size size,
    required double scale,
    required CadPoint2D Function(Offset) screenToCad,
    required Offset Function(CadPoint2D) cadToScreen,
    required Offset effectiveInspectorPos,
    FoldBendLine? selectedBend,
    CadLineSegment? selectedCut,
    CncPunchPrimitive? selectedPunch,
    PerforationPattern? selectedPattern,
    PlanarSheetFace? selectedFace,
  }) {
    return [
                    // In-Place Dimension Editor (converts number tag directly in-place)
                    _buildInPlaceDimensionEditor(viewModel),

                    // 2. Fitting Metadata & Trunking Cover Control Bar (Top Left)
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InkWell(
                            onTap: () => viewModel.setFittingInspectorOpen(true),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B)
                                    .withValues(alpha: 0.88),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(0xFF8B5CF6)
                                      .withValues(alpha: 0.65),
                                  width: 1.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.25),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.tune,
                                    size: 14,
                                    color: Color(0xFFA78BFA),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    (viewModel.detectedFittingMetadata != null &&
                                            viewModel
                                                .detectedFittingMetadata!
                                                .isAssigned &&
                                            viewModel
                                                .detectedFittingMetadata!
                                                .product
                                                .isNotEmpty)
                                        ? '${viewModel.detectedFittingMetadata!.product} (${viewModel.detectedFittingMetadata!.variantName})'
                                        : 'DSF Inspector',
                                    style: const TextStyle(
                                      color: Color(0xFFF1F5F9),
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Cover Control Pill
                          if (viewModel.hasCover)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B)
                                    .withValues(alpha: 0.90),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(0xFF0284C7)
                                      .withValues(alpha: 0.70),
                                  width: 1.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.25),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.shield_outlined,
                                    size: 14,
                                    color: Color(0xFF38BDF8),
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'Cover',
                                    style: TextStyle(
                                      color: Color(0xFFF1F5F9),
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  // Show/Hide Toggle
                                  Tooltip(
                                    message: viewModel.isCoverVisible2D
                                        ? 'Hide Cover (2D)'
                                        : 'Show Cover (2D)',
                                    child: InkWell(
                                      onTap: viewModel.toggleCoverVisibility2D,
                                      borderRadius: BorderRadius.circular(4),
                                      child: Padding(
                                        padding: const EdgeInsets.all(3.0),
                                        child: Icon(
                                          viewModel.isCoverVisible2D
                                              ? Icons.visibility
                                              : Icons.visibility_off,
                                          size: 14,
                                          color: viewModel.isCoverVisible2D
                                              ? const Color(0xFF38BDF8)
                                              : const Color(0xFF94A3B8),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  // Snap to Base / Move Beside Toggle
                                  Tooltip(
                                    message: viewModel.coverPlacementMode2D ==
                                            CoverPlacementMode2D.snappedToBase
                                        ? 'Move Cover Beside Base'
                                        : 'Snap Cover to Base',
                                    child: InkWell(
                                      onTap: () {
                                        if (viewModel.coverPlacementMode2D ==
                                            CoverPlacementMode2D.snappedToBase) {
                                          viewModel.resetCoverBesideBase();
                                        } else {
                                          viewModel.snapCoverToBase();
                                        }
                                      },
                                      borderRadius: BorderRadius.circular(4),
                                      child: Padding(
                                        padding: const EdgeInsets.all(3.0),
                                        child: Icon(
                                          viewModel.coverPlacementMode2D ==
                                                  CoverPlacementMode2D
                                                      .snappedToBase
                                              ? Icons.flip_to_front
                                              : Icons.flip_to_back,
                                          size: 14,
                                          color: const Color(0xFFA78BFA),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  // Reset Position
                                  Tooltip(
                                    message: 'Reset Beside Position',
                                    child: InkWell(
                                      onTap: viewModel.resetCoverBesideBase,
                                      borderRadius: BorderRadius.circular(4),
                                      child: const Padding(
                                        padding: EdgeInsets.all(3.0),
                                        child: Icon(
                                          Icons.refresh,
                                          size: 14,
                                          color: Color(0xFF94A3B8),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            InkWell(
                              onTap: viewModel.createCoverForCurrentFitting,
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0284C7)
                                      .withValues(alpha: 0.90),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: const Color(0xFF38BDF8),
                                    width: 1.2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black
                                          .withValues(alpha: 0.25),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.add_moderator,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'Create Cover',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    // Floating Sketch Palette (Top Right Corner - non-persistent, toggled via toolbar button)
                    if (viewModel.isSketchPaletteOpen)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: StudioSketchPalette(
                          viewModel: viewModel,
                          showGrid: _showGrid,
                          showProfileFill: _showProfileFill,
                          showPoints: _showPoints,
                          onToggleGrid: (val) {
                            setState(() {
                              _showGrid = val;
                            });
                          },
                          onToggleProfileFill: (val) {
                            setState(() {
                              _showProfileFill = val;
                            });
                          },
                          onTogglePoints: (val) {
                            setState(() {
                              _showPoints = val;
                            });
                          },
                          onClose: () {
                            viewModel.setSketchPaletteOpen(false);
                          },
                          onFinishSketch: () {
                            viewModel.setToolMode(StudioToolMode.select);
                            viewModel.setSketchPaletteOpen(false);
                          },
                        ),
                      ),

                    // Floating Constraints Manager Sheet
                    if (viewModel.isConstraintManagerOpen)
                      Positioned(
                        top: 48,
                        left: 12,
                        child: ConstraintManagerSheet(
                          viewModel: viewModel,
                          onClose: () =>
                              viewModel.setConstraintManagerOpen(false),
                        ),
                      ),

                    // Constraint Binding HUD (Interactive prompt banner during constraint creation)
                    if (viewModel.activeConstraintPickType != null)
                      Positioned(
                        top: 12,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: ConstraintBindingHud(viewModel: viewModel),
                        ),
                      ),

                    // 2b. Floating HUD for Interactive Port Edge Picking (W and H)
                    if (viewModel.activePortPickTarget != null)
                      Positioned(
                        top: 12,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFF0284C7),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.touch_app,
                                  color: Color(0xFF38BDF8),
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Select Edge for ${viewModel.activePortPickTarget!.displayName}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (viewModel.hoveredContourEdgeLengthMm !=
                                    null) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0D9488),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '${viewModel.hoveredContourEdgeLengthMm!.toStringAsFixed(1)} mm',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(width: 12),
                                InkWell(
                                  onTap: () => viewModel.cancelPortEdgePick(),
                                  borderRadius: BorderRadius.circular(4),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.15,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'Cancel',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    // 2c. Floating HUD for 1-Click Semantic Port Inference
                    if (viewModel.activeSemanticPortId != null)
                      Positioned(
                        top: 12,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color:
                                    viewModel.activePortInferenceResult != null
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFF0EA5E9),
                                width: 1.8,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.35),
                                  blurRadius: 14,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  viewModel.activePortInferenceResult != null
                                      ? Icons.check_circle_outline
                                      : Icons.ads_click,
                                  color:
                                      viewModel.activePortInferenceResult !=
                                          null
                                      ? const Color(0xFF34D399)
                                      : const Color(0xFF38BDF8),
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                if (viewModel.activePortInferenceResult ==
                                    null) ...[
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Click Opening Edge for ${viewModel.activeSemanticPortId!.toUpperCase()}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const Text(
                                        'Auto-infers Width (W), Sidewalls (H-A/H-B), and Connection Normal',
                                        style: TextStyle(
                                          color: Color(0xFF94A3B8),
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 14),
                                  InkWell(
                                    onTap: () => viewModel
                                        .cancelSemanticPortAssignment(),
                                    borderRadius: BorderRadius.circular(5),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: const Text(
                                        'Cancel',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ),
                                ] else ...[
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Inferred ${viewModel.activePortInferenceResult!.inferredSide.displayName} Port (${viewModel.activeSemanticPortId!.toUpperCase()}):',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        viewModel
                                            .activePortInferenceResult!
                                            .summaryText,
                                        style: const TextStyle(
                                          color: Color(0xFF34D399),
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 14),
                                  ElevatedButton.icon(
                                    onPressed: () => viewModel
                                        .confirmSemanticPortAssignment(),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF10B981),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      elevation: 2,
                                    ),
                                    icon: const Icon(Icons.check, size: 16),
                                    label: const Text(
                                      'Confirm (1-Click)',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: () => viewModel
                                        .cancelSemanticPortAssignment(),
                                    borderRadius: BorderRadius.circular(5),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: const Text(
                                        'Cancel',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),

                    // 2d. Port-Driven Dimension Editor Floating Card (Set 4A)
                    if (_activeEditingPortId != null)
                      Positioned(
                        left: (_portEditorScreenPos?.dx ?? 40.0).clamp(
                          16.0,
                          math.max(16.0, constraints.maxWidth - 300.0),
                        ),
                        top: (_portEditorScreenPos?.dy ?? 80.0).clamp(
                          16.0,
                          math.max(16.0, constraints.maxHeight - 340.0),
                        ),
                        child: _buildPortDimensionEditorCard(viewModel),
                      ),

                    // 3. Tool Mode Selector (+ Bend, + Cut, Punches, Snapping Toggle)
                    if (widget.showInCanvasToolRibbon)
                      Positioned(
                        top: 50,
                        left: 12,
                        right: 12,
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Container(
                            constraints: BoxConstraints(
                              maxWidth: math.max(
                                100.0,
                                constraints.maxWidth - 24.0,
                              ),
                            ),
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.95),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0xFFCBD5E1),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ScrollConfiguration(
                              behavior: ScrollConfiguration.of(context)
                                  .copyWith(
                                    dragDevices: {
                                      PointerDeviceKind.touch,
                                      PointerDeviceKind.mouse,
                                      PointerDeviceKind.trackpad,
                                      PointerDeviceKind.stylus,
                                    },
                                  ),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                physics: const BouncingScrollPhysics(),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _toolButton(
                                      icon: Icons.near_me,
                                      label: 'Select',
                                      active:
                                          viewModel.toolMode ==
                                          StudioToolMode.select,
                                      onTap: () => viewModel.setToolMode(
                                        StudioToolMode.select,
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    _toolButton(
                                      icon: Icons.pan_tool_outlined,
                                      label: 'Pan',
                                      active:
                                          viewModel.toolMode ==
                                          StudioToolMode.pan,
                                      onTap: () => viewModel.setToolMode(
                                        StudioToolMode.pan,
                                      ),
                                    ),
                                    if (viewModel.document.productType
                                            .toLowerCase()
                                            .contains('tee') ||
                                        viewModel.document.productType
                                            .toLowerCase()
                                            .contains('fitting')) ...[
                                      const SizedBox(width: 3),
                                      _toolButton(
                                        icon: viewModel.showPortOpeningBadges
                                            ? Icons.label
                                            : Icons.label_off_outlined,
                                        label: viewModel.showPortOpeningBadges
                                            ? 'W×H Tags: ON'
                                            : 'W×H Tags: OFF',
                                        active: viewModel.showPortOpeningBadges,
                                        onTap:
                                            viewModel.togglePortOpeningBadges,
                                      ),
                                    ],
                                    const SizedBox(width: 3),
                                    _toolButton(
                                      icon: Icons.polyline,
                                      label: '+ Bend',
                                      active:
                                          viewModel.toolMode ==
                                          StudioToolMode.addBend,
                                      onTap: () => viewModel.setToolMode(
                                        StudioToolMode.addBend,
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    _toolButton(
                                      icon: Icons.border_top,
                                      label: '+ Flange',
                                      active:
                                          viewModel.toolMode ==
                                          StudioToolMode.addFlange,
                                      onTap: () => viewModel.setToolMode(
                                        StudioToolMode.addFlange,
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    _toolButton(
                                      icon: Icons.content_cut,
                                      label: '+ Cut',
                                      active:
                                          viewModel.toolMode ==
                                          StudioToolMode.addCut,
                                      onTap: () => viewModel.setToolMode(
                                        StudioToolMode.addCut,
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    _toolButton(
                                      icon: Icons.radio_button_unchecked,
                                      label: 'Round Hole',
                                      active:
                                          viewModel.toolMode ==
                                          StudioToolMode.addPunchRound,
                                      onTap: () => viewModel.setToolMode(
                                        StudioToolMode.addPunchRound,
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    _toolButton(
                                      customIcon: ObroundSlotIcon(
                                        width: 15,
                                        height: 10,
                                        color:
                                            viewModel.toolMode ==
                                                StudioToolMode.addPunchObround
                                            ? const Color(0xFF0284C7)
                                            : const Color(0xFF475569),
                                      ),
                                      label: 'Obround Slot',
                                      active:
                                          viewModel.toolMode ==
                                          StudioToolMode.addPunchObround,
                                      onTap: () => viewModel.setToolMode(
                                        StudioToolMode.addPunchObround,
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    _toolButton(
                                      icon: Icons.crop_square,
                                      label: 'Square',
                                      active:
                                          viewModel.toolMode ==
                                          StudioToolMode.addPunchSquare,
                                      onTap: () => viewModel.setToolMode(
                                        StudioToolMode.addPunchSquare,
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    _toolButton(
                                      icon: Icons.grid_view,
                                      label: 'Perforation',
                                      active:
                                          viewModel.toolMode ==
                                          StudioToolMode.perforationPattern,
                                      onTap: () => viewModel.setToolMode(
                                        StudioToolMode.perforationPattern,
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    _toolButton(
                                      icon: Icons.anchor,
                                      label: 'Anchor',
                                      active:
                                          viewModel.toolMode ==
                                          StudioToolMode.setBaseAnchor,
                                      onTap: () => viewModel.setToolMode(
                                        StudioToolMode.setBaseAnchor,
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    // 2D Draw Tools Dropdown Menu (Step 3 #16)
                                    PopupMenuButton<StudioToolMode>(
                                      tooltip: '2D Draw Tools',
                                      icon: Icon(
                                        Icons.draw_outlined,
                                        size: 15,
                                        color:
                                            (viewModel.toolMode ==
                                                    StudioToolMode
                                                        .drawRectangle ||
                                                viewModel.toolMode ==
                                                    StudioToolMode.drawCircle ||
                                                viewModel.toolMode ==
                                                    StudioToolMode.drawArc ||
                                                viewModel.toolMode ==
                                                    StudioToolMode.drawPolyline)
                                            ? const Color(0xFF0284C7)
                                            : const Color(0xFF475569),
                                      ),
                                      onSelected: (mode) =>
                                          viewModel.setToolMode(mode),
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(
                                          value: StudioToolMode.drawRectangle,
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.crop_3_2,
                                                size: 16,
                                                color: Color(0xFF0F172A),
                                              ),
                                              SizedBox(width: 8),
                                              Text('Rectangle (2-Point)'),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: StudioToolMode.drawCircle,
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.circle_outlined,
                                                size: 16,
                                                color: Color(0xFF0F172A),
                                              ),
                                              SizedBox(width: 8),
                                              Text('Circle (Center-Radius)'),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: StudioToolMode.drawArc,
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.architecture,
                                                size: 16,
                                                color: Color(0xFF0F172A),
                                              ),
                                              SizedBox(width: 8),
                                              Text('Arc (3-Point)'),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: StudioToolMode.drawPolyline,
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.timeline,
                                                size: 16,
                                                color: Color(0xFF0F172A),
                                              ),
                                              SizedBox(width: 8),
                                              Text('Polyline (Continuous)'),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 3),
                                    // 2D Modify Tools Dropdown Menu (Step 4 #17)
                                    PopupMenuButton<String>(
                                      tooltip: '2D Modify Tools',
                                      icon: Icon(
                                        Icons.handyman_outlined,
                                        size: 15,
                                        color:
                                            (viewModel.toolMode ==
                                                    StudioToolMode.modifyMove ||
                                                viewModel.toolMode ==
                                                    StudioToolMode
                                                        .modifyRotate ||
                                                viewModel.toolMode ==
                                                    StudioToolMode
                                                        .modifyMirror ||
                                                viewModel.toolMode ==
                                                    StudioToolMode.modifyOffset)
                                            ? const Color(0xFF0284C7)
                                            : const Color(0xFF475569),
                                      ),
                                      onSelected: (action) {
                                        switch (action) {
                                          case 'move':
                                            viewModel.setToolMode(
                                              StudioToolMode.modifyMove,
                                            );
                                            break;
                                          case 'rotate':
                                            viewModel.setToolMode(
                                              StudioToolMode.modifyRotate,
                                            );
                                            break;
                                          case 'mirror':
                                            viewModel.setToolMode(
                                              StudioToolMode.modifyMirror,
                                            );
                                            break;
                                          case 'offset':
                                            viewModel.setToolMode(
                                              StudioToolMode.modifyOffset,
                                            );
                                            break;
                                          case 'duplicate':
                                            viewModel.duplicateSelectedEntities(
                                              10.0,
                                              10.0,
                                            );
                                            break;
                                          case 'delete':
                                            viewModel.deleteSelectedEntities();
                                            break;
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(
                                          value: 'move',
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.open_with,
                                                size: 16,
                                                color: Color(0xFF0F172A),
                                              ),
                                              SizedBox(width: 8),
                                              Text('Move Selected'),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'rotate',
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.rotate_right,
                                                size: 16,
                                                color: Color(0xFF0F172A),
                                              ),
                                              SizedBox(width: 8),
                                              Text('Rotate Selected'),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'mirror',
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.flip,
                                                size: 16,
                                                color: Color(0xFF0F172A),
                                              ),
                                              SizedBox(width: 8),
                                              Text('Mirror Selected (Copy)'),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'offset',
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.copy_all,
                                                size: 16,
                                                color: Color(0xFF0F172A),
                                              ),
                                              SizedBox(width: 8),
                                              Text('Offset Contour'),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuDivider(),
                                        const PopupMenuItem(
                                          value: 'duplicate',
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.content_copy,
                                                size: 16,
                                                color: Color(0xFF0F172A),
                                              ),
                                              SizedBox(width: 8),
                                              Text('Duplicate (+10, +10 mm)'),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.delete_outline,
                                                size: 16,
                                                color: Color(0xFFEF4444),
                                              ),
                                              SizedBox(width: 8),
                                              Text(
                                                'Delete Selected',
                                                style: TextStyle(
                                                  color: Color(0xFFEF4444),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 3),
                                    // Associative Dimension Tool (Step 6 #19)
                                    _toolButton(
                                      icon: Icons.straighten,
                                      label: 'Dim',
                                      active:
                                          viewModel.toolMode ==
                                          StudioToolMode.addDimension,
                                      onTap: () => viewModel.setToolMode(
                                        viewModel.toolMode ==
                                                StudioToolMode.addDimension
                                            ? StudioToolMode.select
                                            : StudioToolMode.addDimension,
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    // Geometric Constraints Tool Menu
                                    PopupMenuButton<CadConstraintType>(
                                      tooltip: 'Apply Geometric Constraint',
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color:
                                              viewModel
                                                      .activeConstraintPickType !=
                                                  null
                                              ? const Color(0xFFE0F2FE)
                                              : const Color(0xFFF8FAFC),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                          border: Border.all(
                                            color:
                                                viewModel
                                                        .activeConstraintPickType !=
                                                    null
                                                ? const Color(0xFF0284C7)
                                                : const Color(0xFFE2E8F0),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.link,
                                              size: 13,
                                              color:
                                                  viewModel
                                                          .activeConstraintPickType !=
                                                      null
                                                  ? const Color(0xFF0284C7)
                                                  : const Color(0xFF475569),
                                            ),
                                            const SizedBox(width: 5),
                                            Text(
                                              'Constraint',
                                              style: TextStyle(
                                                color:
                                                    viewModel
                                                            .activeConstraintPickType !=
                                                        null
                                                    ? const Color(0xFF0284C7)
                                                    : const Color(0xFF475569),
                                                fontSize: 11,
                                                fontWeight:
                                                    viewModel
                                                            .activeConstraintPickType !=
                                                        null
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                              ),
                                            ),
                                            const SizedBox(width: 2),
                                            const Icon(
                                              Icons.arrow_drop_down,
                                              size: 14,
                                              color: Color(0xFF64748B),
                                            ),
                                          ],
                                        ),
                                      ),
                                      onSelected: (type) {
                                        viewModel.startInteractiveConstraint(
                                          type,
                                        );
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(
                                          value: CadConstraintType.coincident,
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.adjust,
                                                size: 16,
                                                color: Color(0xFF2563EB),
                                              ),
                                              SizedBox(width: 8),
                                              Text(
                                                'Coincident (Snap points together)',
                                              ),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: CadConstraintType.distance,
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.straighten,
                                                size: 16,
                                                color: Color(0xFF2563EB),
                                              ),
                                              SizedBox(width: 8),
                                              Text(
                                                'Distance / Clearance (Bind to Edge)',
                                              ),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: CadConstraintType.horizontal,
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.horizontal_rule,
                                                size: 16,
                                                color: Color(0xFF2563EB),
                                              ),
                                              SizedBox(width: 8),
                                              Text('Horizontal Alignment'),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: CadConstraintType.vertical,
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.vertical_distribute,
                                                size: 16,
                                                color: Color(0xFF2563EB),
                                              ),
                                              SizedBox(width: 8),
                                              Text('Vertical Alignment'),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: CadConstraintType.parallel,
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.reorder,
                                                size: 16,
                                                color: Color(0xFF2563EB),
                                              ),
                                              SizedBox(width: 8),
                                              Text('Parallel'),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value:
                                              CadConstraintType.perpendicular,
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.square_foot,
                                                size: 16,
                                                color: Color(0xFF2563EB),
                                              ),
                                              SizedBox(width: 8),
                                              Text('Perpendicular'),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: CadConstraintType.symmetric,
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.splitscreen,
                                                size: 16,
                                                color: Color(0xFF2563EB),
                                              ),
                                              SizedBox(width: 8),
                                              Text(
                                                'Symmetric about Centerline',
                                              ),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: CadConstraintType.concentric,
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.album_outlined,
                                                size: 16,
                                                color: Color(0xFF2563EB),
                                              ),
                                              SizedBox(width: 8),
                                              Text('Concentric'),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      width: 1,
                                      height: 18,
                                      color: const Color(0xFFCBD5E1),
                                    ),
                                    const SizedBox(width: 6),
                                    // Magnetic Snapping Toggle
                                    _toolButton(
                                      icon: viewModel.magneticSnapEnabled
                                          ? Icons.gps_fixed
                                          : Icons.gps_not_fixed,
                                      label: viewModel.magneticSnapEnabled
                                          ? 'Snap: ON'
                                          : 'Snap: OFF',
                                      active: viewModel.magneticSnapEnabled,
                                      onTap: viewModel.toggleMagneticSnap,
                                    ),
                                    const SizedBox(width: 3),
                                    // Snap Mode Dropdown / Settings Menu
                                    PopupMenuButton<SnapType>(
                                      tooltip: 'Snap Modes',
                                      icon: const Icon(
                                        Icons.tune,
                                        size: 15,
                                        color: Color(0xFF475569),
                                      ),
                                      onSelected: (type) =>
                                          viewModel.toggleSnapSetting(type),
                                      itemBuilder: (context) {
                                        final s = viewModel.snapSettings;
                                        return [
                                          _snapMenuItem(
                                            SnapType.endpoint,
                                            'Endpoint 🔲',
                                            s.enableEndpoint,
                                          ),
                                          _snapMenuItem(
                                            SnapType.midpoint,
                                            'Midpoint 🔺',
                                            s.enableMidpoint,
                                          ),
                                          _snapMenuItem(
                                            SnapType.center,
                                            'Center ⭕',
                                            s.enableCenter,
                                          ),
                                          _snapMenuItem(
                                            SnapType.intersection,
                                            'Intersection ✖',
                                            s.enableIntersection,
                                          ),
                                          _snapMenuItem(
                                            SnapType.perpendicular,
                                            'Perpendicular ⟂',
                                            s.enablePerpendicular,
                                          ),
                                          _snapMenuItem(
                                            SnapType.tangent,
                                            'Tangent ⊚',
                                            s.enableTangent,
                                          ),
                                          _snapMenuItem(
                                            SnapType.quadrant,
                                            'Quadrant 🔷',
                                            s.enableQuadrant,
                                          ),
                                          _snapMenuItem(
                                            SnapType.nearest,
                                            'Nearest ⧗',
                                            s.enableNearest,
                                          ),
                                          _snapMenuItem(
                                            SnapType.grid,
                                            'Grid Snap ⊞',
                                            s.enableGrid,
                                          ),
                                        ];
                                      },
                                    ),
                                    const SizedBox(width: 3),
                                    // Ortho Tracking Toggle
                                    _toolButton(
                                      icon: Icons.near_me_disabled,
                                      label:
                                          viewModel
                                              .snapSettings
                                              .enableOrthoTracking
                                          ? 'Ortho: ON'
                                          : 'Ortho: OFF',
                                      active: viewModel
                                          .snapSettings
                                          .enableOrthoTracking,
                                      onTap: viewModel.toggleOrthoTracking,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                    // 4. Draggable Floating Property Inspector
                    if (widget.renderFloatingInspectors &&
                        viewModel.isPropertyInspectorOpen)
                      Positioned(
                        left: effectiveInspectorPos.dx.clamp(
                          8.0,
                          math.max(8.0, constraints.maxWidth - 280.0),
                        ),
                        top: effectiveInspectorPos.dy.clamp(
                          8.0,
                          math.max(8.0, constraints.maxHeight - 120.0),
                        ),
                        child: _buildFloatingInspector(
                          viewModel: viewModel,
                          effectiveInspectorPos: effectiveInspectorPos,
                        ),
                      ),

                    // 4b. Draggable Active Tool Property Inspector (Configured BEFORE stamping)
                    if (widget.renderFloatingInspectors &&
                        viewModel.toolMode != StudioToolMode.select &&
                        viewModel.toolMode != StudioToolMode.pan &&
                        viewModel.toolMode != StudioToolMode.addBend &&
                        viewModel.toolMode != StudioToolMode.addFlange &&
                        viewModel.toolMode != StudioToolMode.addCut &&
                        viewModel.toolMode != StudioToolMode.setBaseAnchor)
                      Positioned(
                        left: effectiveInspectorPos.dx.clamp(
                          8.0,
                          math.max(8.0, constraints.maxWidth - 290.0),
                        ),
                        top: effectiveInspectorPos.dy.clamp(
                          8.0,
                          math.max(8.0, constraints.maxHeight - 120.0),
                        ),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (details) {
                            _dragStartGlobal = details.globalPosition;
                            _dragStartPanel = effectiveInspectorPos;
                          },
                          onPanUpdate: (details) {
                            if (_dragStartGlobal != null &&
                                _dragStartPanel != null) {
                              setState(() {
                                _inspectorOffset =
                                    _dragStartPanel! +
                                    (details.globalPosition -
                                        _dragStartGlobal!);
                              });
                            }
                          },
                          child: ActiveToolPropertySheet(
                            viewModel: viewModel,
                            onClose: () =>
                                viewModel.setToolMode(StudioToolMode.select),
                            onDragStartHeader: (details) {
                              _dragStartGlobal = details.globalPosition;
                              _dragStartPanel = effectiveInspectorPos;
                            },
                            onDragHeader: (details) {
                              if (_dragStartGlobal != null &&
                                  _dragStartPanel != null) {
                                setState(() {
                                  _inspectorOffset =
                                      _dragStartPanel! +
                                      (details.globalPosition -
                                          _dragStartGlobal!);
                                });
                              }
                            },
                          ),
                        ),
                      ),

                    // Floating Reopen Button if Inspector is closed
                    if (widget.renderFloatingInspectors &&
                        !viewModel.isPropertyInspectorOpen)
                      Positioned(
                        top: 12,
                        right: 180,
                        child: InkWell(
                          onTap: () {
                            viewModel.setPropertyInspectorOpen(true);
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0xFF0284C7),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.tune,
                                  size: 14,
                                  color: Color(0xFF0284C7),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  selectedBend != null
                                      ? 'Open ${selectedBend.id} Properties'
                                      : (selectedPunch != null
                                            ? 'Open ${selectedPunch.id} Properties'
                                            : (viewModel
                                                          .selectedEntityIds
                                                          .length >
                                                      1
                                                  ? 'Properties (${viewModel.selectedEntityIds.length} Selected)'
                                                  : (selectedPattern != null
                                                        ? 'Open ${selectedPattern.id} Properties'
                                                        : (selectedFace != null
                                                              ? 'Open ${selectedFace.id} Properties'
                                                              : 'Properties (Ctrl+1)')))),
                                  style: const TextStyle(
                                    color: Color(0xFF0284C7),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    // 5. Studio Bottom Bar (Floating Navigation Toolstrip & TEXT COMMANDS Prompt)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: StudioBottomBar(viewModel: viewModel),
                    ),

                    // 6. Ultra-Small Micro Layer Legend (Hovers neatly above bottom bar)
                    Positioned(
                      bottom: 36,
                      right: 12,
                      child: _buildCompactLegend(),
                    ),
    ];
  }
}
