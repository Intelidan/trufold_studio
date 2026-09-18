// =============================================================================
// active_tool_property_sheet.dart
//
// Floating On-Canvas Property Inspector for the Active Creation Tool.
// Opens automatically as soon as a toolbar button (+ Round Hole, + Obround,
// + Square, + Perforation Pattern, or Chamfer) is clicked.
// Allows the user to configure exact dimensions and patterns BEFORE clicking
// the flat blank to stamp or apply.
//
// Unified Perforation Tool provides:
// 1. Auto-Nest (CMS Standard): Fits modular perforation pattern to any selected
//    planar surface (bed floor, side wall) with real-time interactive preview.
// 2. Manual Stamping: Configurable grid parameters with click-to-stamp.
// =============================================================================

import 'package:flutter/material.dart';
import '../../models/cnc_punch_primitive.dart';
import '../../models/planar_sheet_face.dart';
import '../../engine/cnc_turret_engine.dart';
import '../../viewmodels/sheet_metal_studio_viewmodel.dart';
import 'rotation_dial_widget.dart';
import 'cad_number_spinner.dart';

class ActiveToolPropertySheet extends StatefulWidget {
  final SheetMetalStudioViewModel viewModel;
  final VoidCallback? onClose;
  final GestureDragStartCallback? onDragStartHeader;
  final GestureDragUpdateCallback? onDragHeader;

  const ActiveToolPropertySheet({
    super.key,
    required this.viewModel,
    this.onClose,
    this.onDragStartHeader,
    this.onDragHeader,
  });

  @override
  State<ActiveToolPropertySheet> createState() => _ActiveToolPropertySheetState();
}

class _ActiveToolPropertySheetState extends State<ActiveToolPropertySheet> {
  // 0: Auto-Nest (CMS Standard), 1: Manual Stamp
  int _perfTab = 0;

  // CMS Auto-nesting parameters
  String? _selectedFaceId;
  PunchType _holeType = PunchType.obroundSlot;
  double _slotWidth = 7.0;
  double _slotLength = 30.0;
  double _diameterMm = 8.0;
  double _squareSize = 10.0;
  double _rectWidth = 25.0;
  double _rectHeight = 10.0;
  double _pitchX = 50.0;
  double _pitchY = 80.0;
  double _staggerDistance = 25.0;
  double _rotationDeg = 0.0;
  bool _staggered = true;
  bool _includeCouplers = false;

  @override
  void initState() {
    super.initState();
    _initFaceSelection();
    if (widget.viewModel.toolMode == StudioToolMode.perforationPattern) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updatePerforationPreview();
      });
    }
  }

  @override
  void didUpdateWidget(covariant ActiveToolPropertySheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.viewModel.toolMode == StudioToolMode.perforationPattern) {
      final curSelected = widget.viewModel.selectedFaceId;
      if (curSelected != null && curSelected != _selectedFaceId) {
        _selectedFaceId = curSelected;
        _updateDefaultsForFace(curSelected);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _updatePerforationPreview();
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.viewModel.clearPreviewPerforation();
    });
    super.dispose();
  }

  void _initFaceSelection() {
    final faces = widget.viewModel.document.faces;
    final initialId = widget.viewModel.selectedFaceId;

    if (initialId != null && faces.any((f) => f.id == initialId)) {
      _selectedFaceId = initialId;
    } else {
      final base = faces.cast<PlanarSheetFace?>().firstWhere(
        (f) => f?.role == FaceRole.baseFloor,
        orElse: () => null,
      );
      _selectedFaceId = base?.id ?? (faces.isNotEmpty ? faces.first.id : null);
    }

    if (_selectedFaceId != null) {
      _updateDefaultsForFace(_selectedFaceId!);
    }
  }

  void _updateDefaultsForFace(String faceId) {
    final face = _getFace(faceId);
    if (face == null) return;

    if (face.role == FaceRole.sideWall) {
      _rotationDeg = 90.0; // Side wall slots run longitudinally
      _includeCouplers = true;
      _pitchX = 25.0;
    } else {
      _rotationDeg = 0.0; // Bed floor slots run transversely across width
      _includeCouplers = false;
      _pitchX = 50.0;
    }
  }

  PlanarSheetFace? _getFace(String? faceId) {
    if (faceId == null) return null;
    try {
      return widget.viewModel.document.faces.firstWhere((f) => f.id == faceId);
    } catch (_) {
      return null;
    }
  }

  void _updatePerforationPreview() {
    if (widget.viewModel.toolMode != StudioToolMode.perforationPattern) return;

    if (_perfTab == 1) {
      // In manual mode, clear the auto-nest preview so user can use manual rubber-band ghost
      widget.viewModel.clearPreviewPerforation();
      return;
    }

    final face = _getFace(_selectedFaceId);
    if (face == null || face.vertices.isEmpty) {
      widget.viewModel.clearPreviewPerforation();
      return;
    }

    final effWidth = _holeType == PunchType.square
        ? _squareSize
        : (_holeType == PunchType.rectangle ? _rectHeight : _slotWidth);
    final effLength = _holeType == PunchType.square
        ? _squareSize
        : (_holeType == PunchType.rectangle ? _rectWidth : _slotLength);
    final effDiameter = _holeType == PunchType.square ? _squareSize : _diameterMm;

    final pattern = CncTurretEngine.autoNestPerforationOnFace(
      face: face,
      doc: widget.viewModel.document,
      holeType: _holeType,
      slotWidth: effWidth,
      slotLength: effLength,
      diameterMm: effDiameter,
      pitchY: _pitchY,
      overridePitchX: _pitchX,
      staggerDistance: _staggerDistance,
      endMargin: 50.0,
      rotationDeg: _rotationDeg,
      staggered: _staggered,
      patternId: 'PREVIEW_PERF',
    );

    List<CncPunchPrimitive>? previewCouplers;
    if (_includeCouplers) {
      previewCouplers = CncTurretEngine.generateSideRailCouplerSlots(
        doc: widget.viewModel.document,
        slotWidth: _slotWidth,
        slotLength: 20.0,
        endOffset: 25.0,
        verticalSpacing: 25.0,
      );
    }

    widget.viewModel.setPreviewPerforation(pattern, couplers: previewCouplers);
  }

  void _handleClose() {
    widget.viewModel.clearPreviewPerforation();
    widget.viewModel.setToolMode(StudioToolMode.select);
    widget.onClose?.call();
  }

  void _applyCmsPerforation() {
    if (_selectedFaceId == null) return;

    final effWidth = _holeType == PunchType.square
        ? _squareSize
        : (_holeType == PunchType.rectangle ? _rectHeight : _slotWidth);
    final effLength = _holeType == PunchType.square
        ? _squareSize
        : (_holeType == PunchType.rectangle ? _rectWidth : _slotLength);
    final effDiameter = _holeType == PunchType.square ? _squareSize : _diameterMm;

    widget.viewModel.autoNestPerforationOnFace(
      faceId: _selectedFaceId,
      holeType: _holeType,
      slotWidth: effWidth,
      slotLength: effLength,
      diameterMm: effDiameter,
      pitchY: _pitchY,
      overridePitchX: _pitchX,
      staggerDistance: _staggerDistance,
      endMargin: 50.0,
      rotationDeg: _rotationDeg,
      staggered: _staggered,
    );

    if (_includeCouplers) {
      widget.viewModel.stampSideRailCouplers(
        slotWidth: _slotWidth,
        slotLength: 20.0,
        endOffset: 25.0,
        verticalSpacing: 25.0,
      );
    }

    widget.viewModel.clearPreviewPerforation();
    widget.viewModel.setToolMode(StudioToolMode.select);
  }

  @override
  Widget build(BuildContext context) {
    final mode = widget.viewModel.toolMode;
    if (mode == StudioToolMode.select ||
        mode == StudioToolMode.pan ||
        mode == StudioToolMode.addCut ||
        mode == StudioToolMode.setBaseAnchor) {
      return const SizedBox.shrink();
    }

    final cfg = widget.viewModel.toolConfig;
    const themeColor = Color(0xFF0284C7);

    String title;
    IconData icon;
    Widget body;

    switch (mode) {
      case StudioToolMode.addPunchRound:
      case StudioToolMode.drawCircle:
        title = 'CIRCLE / HOLE PUNCH';
        icon = Icons.radio_button_unchecked;
        body = _buildRoundHoleBody(cfg);
        break;
      case StudioToolMode.addPunchObround:
        title = 'OBROUND SLOT';
        icon = Icons.crop_portrait;
        body = _buildObroundSlotBody(cfg);
        break;
      case StudioToolMode.addPunchSquare:
      case StudioToolMode.drawRectangle:
        title = 'RECTANGLE / SQUARE CUTOUT';
        icon = Icons.crop_square;
        body = _buildSquareBody(cfg);
        break;
      case StudioToolMode.addBend:
      case StudioToolMode.addFlange:
        title = mode == StudioToolMode.addFlange ? 'RETURN FLANGE' : 'BEND LINE';
        icon = mode == StudioToolMode.addFlange ? Icons.border_outer : Icons.alt_route;
        body = _buildBendFlangeBody();
        break;
      case StudioToolMode.perforationPattern:
        title = 'PERFORATION TOOLING';
        icon = Icons.grid_view;
        body = _buildPerforationBody(cfg);
        break;
      case StudioToolMode.cornerChamfer:
        title = 'CORNER CHAMFER (45°)';
        icon = Icons.architecture;
        body = _buildChamferBody(cfg);
        break;
      default:
        return const SizedBox.shrink();
    }

    final panelWidth = mode == StudioToolMode.perforationPattern ? 285.0 : 240.0;
    final maxPanelHeight = (MediaQuery.of(context).size.height - 120.0).clamp(260.0, 700.0);

    return Container(
      width: panelWidth,
      constraints: BoxConstraints(maxHeight: maxPanelHeight),
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6.0),
        border: Border.all(color: themeColor.withValues(alpha: 0.6), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12.0,
            offset: const Offset(0, 3),
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
              Expanded(
                child: GestureDetector(
                  onPanStart: widget.onDragStartHeader,
                  onPanUpdate: widget.onDragHeader,
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      const Icon(Icons.drag_indicator, size: 12, color: Color(0xFF94A3B8)),
                      const SizedBox(width: 3),
                      Icon(icon, size: 13, color: themeColor),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          title,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: _handleClose,
                  child: const Padding(
                    padding: EdgeInsets.all(4.0),
                    child: Icon(Icons.close, size: 14, color: Color(0xFF64748B)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Flexible(
            child: SingleChildScrollView(
              child: body,
            ),
          ),
          const SizedBox(height: 6),
          // Helper caption (for stamping modes)
          if (mode != StudioToolMode.perforationPattern || _perfTab == 1)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F9FF),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: const Color(0xFFBAE6FD)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.touch_app, size: 10, color: Color(0xFF0284C7)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      mode == StudioToolMode.cornerChamfer
                          ? 'Click corner vertex to cut'
                          : 'Click flat blank to stamp',
                      style: const TextStyle(
                        color: Color(0xFF0284C7),
                        fontSize: 8,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Perforation Tooling Body (Unified CMS Auto-Nest + Manual Stamping)
  // ---------------------------------------------------------------------------
  Widget _buildPerforationBody(ActiveToolConfig cfg) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mode Selector: Auto-Nest (CMS) vs Manual Stamp
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.all(2),
          child: Row(
            children: [
              Expanded(
                child: _tabButton('Auto-Nest (CMS)', _perfTab == 0, () {
                  setState(() => _perfTab = 0);
                  _updatePerforationPreview();
                }),
              ),
              Expanded(
                child: _tabButton('Manual Stamp', _perfTab == 1, () {
                  setState(() => _perfTab = 1);
                  _updatePerforationPreview();
                }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        if (_perfTab == 0)
          _buildCmsAutoNestTab()
        else
          _buildManualStampTab(cfg),
      ],
    );
  }

  Widget _buildCmsAutoNestTab() {
    final faces = widget.viewModel.document.faces;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Target Surface Dropdown
        const Text(
          'TARGET SURFACE',
          style: TextStyle(color: Color(0xFF64748B), fontSize: 8, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 3),
        if (faces.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFCBD5E1), width: 0.8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isDense: true,
                isExpanded: true,
                value: faces.any((f) => f.id == _selectedFaceId) ? _selectedFaceId : faces.first.id,
                items: faces.map((f) {
                  final label = f.label.isNotEmpty ? f.label : f.id;
                  final roleName = f.role.name;
                  return DropdownMenuItem(
                    value: f.id,
                    child: Row(
                      children: [
                        Icon(
                          f.role == FaceRole.baseFloor
                              ? Icons.layers
                              : f.role == FaceRole.sideWall
                                  ? Icons.view_sidebar
                                  : Icons.crop_din,
                          size: 13,
                          color: const Color(0xFF0284C7),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            '$label ($roleName)',
                            style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedFaceId = val;
                      _updateDefaultsForFace(val);
                    });
                    _updatePerforationPreview();
                  }
                },
              ),
            ),
          ),
        const SizedBox(height: 6),

        // 2. Hole Type Selector Tabs
        const Text(
          'HOLE TYPE',
          style: TextStyle(color: Color(0xFF64748B), fontSize: 8, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            Expanded(
              child: _chip('Obround', _holeType == PunchType.obroundSlot, () {
                setState(() => _holeType = PunchType.obroundSlot);
                _updatePerforationPreview();
              }),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: _chip('Round', _holeType == PunchType.roundHole, () {
                setState(() => _holeType = PunchType.roundHole);
                _updatePerforationPreview();
              }),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: _chip('Square', _holeType == PunchType.square, () {
                setState(() => _holeType = PunchType.square);
                _updatePerforationPreview();
              }),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: _chip('Rect', _holeType == PunchType.rectangle, () {
                setState(() => _holeType = PunchType.rectangle);
                _updatePerforationPreview();
              }),
            ),
          ],
        ),
        const SizedBox(height: 4),

        // 3. Dynamic Dimension Inputs for Selected Hole Type
        if (_holeType == PunchType.obroundSlot) ...[
          Row(
            children: [
              Expanded(
                child: _doubleInput(
                  label: 'Length (L)',
                  val: _slotLength,
                  step: 1.0,
                  fractionDigits: 0,
                  onChanged: (v) {
                    setState(() => _slotLength = v.clamp(10.0, 80.0));
                    _updatePerforationPreview();
                  },
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _doubleInput(
                  label: 'Width (W)',
                  val: _slotWidth,
                  step: 0.5,
                  fractionDigits: 1,
                  onChanged: (v) {
                    setState(() => _slotWidth = v.clamp(3.0, 25.0));
                    _updatePerforationPreview();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Expanded(
                child: _chip('30×7 Std', _slotLength == 30.0 && _slotWidth == 7.0, () {
                  setState(() {
                    _slotLength = 30.0;
                    _slotWidth = 7.0;
                  });
                  _updatePerforationPreview();
                }),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: _chip('25×7 EN', _slotLength == 25.0 && _slotWidth == 7.0, () {
                  setState(() {
                    _slotLength = 25.0;
                    _slotWidth = 7.0;
                  });
                  _updatePerforationPreview();
                }),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: _chip('20×9 HD', _slotLength == 20.0 && _slotWidth == 9.0, () {
                  setState(() {
                    _slotLength = 20.0;
                    _slotWidth = 9.0;
                  });
                  _updatePerforationPreview();
                }),
              ),
            ],
          ),
        ] else if (_holeType == PunchType.roundHole) ...[
          _doubleInput(
            label: 'Diameter (Ø)',
            val: _diameterMm,
            step: 0.5,
            fractionDigits: 1,
            onChanged: (v) {
              setState(() => _diameterMm = v.clamp(3.0, 40.0));
              _updatePerforationPreview();
            },
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Expanded(
                child: _chip('Ø6 mm', _diameterMm == 6.0, () {
                  setState(() => _diameterMm = 6.0);
                  _updatePerforationPreview();
                }),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: _chip('Ø8 mm', _diameterMm == 8.0, () {
                  setState(() => _diameterMm = 8.0);
                  _updatePerforationPreview();
                }),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: _chip('Ø10 mm', _diameterMm == 10.0, () {
                  setState(() => _diameterMm = 10.0);
                  _updatePerforationPreview();
                }),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: _chip('Ø12 mm', _diameterMm == 12.0, () {
                  setState(() => _diameterMm = 12.0);
                  _updatePerforationPreview();
                }),
              ),
            ],
          ),
        ] else if (_holeType == PunchType.square) ...[
          _doubleInput(
            label: 'Square Size (S)',
            val: _squareSize,
            step: 1.0,
            fractionDigits: 0,
            onChanged: (v) {
              setState(() => _squareSize = v.clamp(4.0, 40.0));
              _updatePerforationPreview();
            },
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Expanded(
                child: _chip('8×8 mm', _squareSize == 8.0, () {
                  setState(() => _squareSize = 8.0);
                  _updatePerforationPreview();
                }),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: _chip('10×10 mm', _squareSize == 10.0, () {
                  setState(() => _squareSize = 10.0);
                  _updatePerforationPreview();
                }),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: _chip('12×12 mm', _squareSize == 12.0, () {
                  setState(() => _squareSize = 12.0);
                  _updatePerforationPreview();
                }),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: _chip('15×15 mm', _squareSize == 15.0, () {
                  setState(() => _squareSize = 15.0);
                  _updatePerforationPreview();
                }),
              ),
            ],
          ),
        ] else if (_holeType == PunchType.rectangle) ...[
          Row(
            children: [
              Expanded(
                child: _doubleInput(
                  label: 'Length (L)',
                  val: _rectWidth,
                  step: 1.0,
                  fractionDigits: 0,
                  onChanged: (v) {
                    setState(() => _rectWidth = v.clamp(8.0, 80.0));
                    _updatePerforationPreview();
                  },
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _doubleInput(
                  label: 'Width (W)',
                  val: _rectHeight,
                  step: 1.0,
                  fractionDigits: 0,
                  onChanged: (v) {
                    setState(() => _rectHeight = v.clamp(4.0, 40.0));
                    _updatePerforationPreview();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Expanded(
                child: _chip('20×10', _rectWidth == 20.0 && _rectHeight == 10.0, () {
                  setState(() {
                    _rectWidth = 20.0;
                    _rectHeight = 10.0;
                  });
                  _updatePerforationPreview();
                }),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: _chip('25×12', _rectWidth == 25.0 && _rectHeight == 12.0, () {
                  setState(() {
                    _rectWidth = 25.0;
                    _rectHeight = 12.0;
                  });
                  _updatePerforationPreview();
                }),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: _chip('30×15', _rectWidth == 30.0 && _rectHeight == 15.0, () {
                  setState(() {
                    _rectWidth = 30.0;
                    _rectHeight = 15.0;
                  });
                  _updatePerforationPreview();
                }),
              ),
            ],
          ),
        ],
        const SizedBox(height: 5),

        // 4. Pitches: Both Pitch X and Pitch Y Editable
        Row(
          children: [
            Expanded(
              child: _doubleInput(
                label: 'Pitch X (Width)',
                val: _pitchX,
                step: 5.0,
                fractionDigits: 0,
                onChanged: (v) {
                  setState(() => _pitchX = v.clamp(15.0, 200.0));
                  _updatePerforationPreview();
                },
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _doubleInput(
                label: 'Pitch Y (Length)',
                val: _pitchY,
                step: 5.0,
                fractionDigits: 0,
                onChanged: (v) {
                  setState(() => _pitchY = v.clamp(20.0, 250.0));
                  _updatePerforationPreview();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),

        // 5. Stagger and Alignment
        Row(
          children: [
            Expanded(
              child: _doubleInput(
                label: 'Stagger (mm)',
                val: _staggerDistance,
                step: 5.0,
                fractionDigits: 0,
                onChanged: (v) {
                  setState(() => _staggerDistance = v.clamp(0.0, 80.0));
                  _updatePerforationPreview();
                },
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: InkWell(
                onTap: () {
                  setState(() => _staggered = !_staggered);
                  _updatePerforationPreview();
                },
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: _staggered ? const Color(0xFFE0F2FE) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: _staggered ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      _staggered ? 'Staggered (CMS)' : 'Straight Grid',
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.bold,
                        color: _staggered ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // 6. Interactive Rotation Dial
        RotationDialWidget(
          angleDeg: _rotationDeg,
          onAngleChanged: (deg) {
            setState(() => _rotationDeg = deg);
            _updatePerforationPreview();
          },
          label: 'Pattern Hole Rotation',
        ),
        const SizedBox(height: 5),

        // 7. Couplers Checkbox
        InkWell(
          onTap: () {
            setState(() => _includeCouplers = !_includeCouplers);
            _updatePerforationPreview();
          },
          child: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: Checkbox(
                  value: _includeCouplers,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (v) {
                    setState(() => _includeCouplers = v ?? false);
                    _updatePerforationPreview();
                  },
                ),
              ),
              const SizedBox(width: 4),
              const Expanded(
                child: Text(
                  'Side-rail coupler slot pairs',
                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 5),

        // Live Graphic Indicator Badge
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFF86EFAC)),
          ),
          child: const Row(
            children: [
              Icon(Icons.visibility, size: 11, color: Color(0xFF16A34A)),
              SizedBox(width: 5),
              Expanded(
                child: Text(
                  'Live pattern preview active on surface',
                  style: TextStyle(
                    color: Color(0xFF15803D),
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),

        // Apply Button
        SizedBox(
          width: double.infinity,
          height: 26,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.bolt, size: 13),
            label: const Text(
              'Apply to Surface',
              style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
              foregroundColor: Colors.white,
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            onPressed: _applyCmsPerforation,
          ),
        ),
      ],
    );
  }

  Widget _buildManualStampTab(ActiveToolConfig cfg) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Hole Type Selector Tabs
        const Text(
          'HOLE TYPE',
          style: TextStyle(color: Color(0xFF64748B), fontSize: 8, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            Expanded(
              child: _chip('Obround', cfg.patternHoleType == PunchType.obroundSlot, () {
                cfg.patternHoleType = PunchType.obroundSlot;
                widget.viewModel.updateToolConfig();
              }),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: _chip('Round', cfg.patternHoleType == PunchType.roundHole, () {
                cfg.patternHoleType = PunchType.roundHole;
                widget.viewModel.updateToolConfig();
              }),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: _chip('Square', cfg.patternHoleType == PunchType.square, () {
                cfg.patternHoleType = PunchType.square;
                widget.viewModel.updateToolConfig();
              }),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: _chip('Rect', cfg.patternHoleType == PunchType.rectangle, () {
                cfg.patternHoleType = PunchType.rectangle;
                widget.viewModel.updateToolConfig();
              }),
            ),
          ],
        ),
        const SizedBox(height: 4),

        // 2. Dynamic Dimension Inputs for Selected Hole Type
        if (cfg.patternHoleType == PunchType.obroundSlot) ...[
          Row(
            children: [
              Expanded(
                child: _doubleInput(
                  label: 'Length (L)',
                  val: cfg.patternSlotWidth,
                  step: 1.0,
                  fractionDigits: 0,
                  onChanged: (v) {
                    cfg.patternSlotWidth = v.clamp(10.0, 80.0);
                    widget.viewModel.updateToolConfig();
                  },
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _doubleInput(
                  label: 'Width (W)',
                  val: cfg.patternSlotHeight,
                  step: 0.5,
                  fractionDigits: 1,
                  onChanged: (v) {
                    cfg.patternSlotHeight = v.clamp(3.0, 25.0);
                    widget.viewModel.updateToolConfig();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Expanded(
                child: _chip('30×7 Std', cfg.patternSlotWidth == 30.0 && cfg.patternSlotHeight == 7.0, () {
                  cfg.patternSlotWidth = 30.0;
                  cfg.patternSlotHeight = 7.0;
                  widget.viewModel.updateToolConfig();
                }),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: _chip('25×7 EN', cfg.patternSlotWidth == 25.0 && cfg.patternSlotHeight == 7.0, () {
                  cfg.patternSlotWidth = 25.0;
                  cfg.patternSlotHeight = 7.0;
                  widget.viewModel.updateToolConfig();
                }),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: _chip('20×9 HD', cfg.patternSlotWidth == 20.0 && cfg.patternSlotHeight == 9.0, () {
                  cfg.patternSlotWidth = 20.0;
                  cfg.patternSlotHeight = 9.0;
                  widget.viewModel.updateToolConfig();
                }),
              ),
            ],
          ),
        ] else if (cfg.patternHoleType == PunchType.roundHole) ...[
          _doubleInput(
            label: 'Diameter (Ø)',
            val: cfg.patternDiameter,
            step: 0.5,
            fractionDigits: 1,
            onChanged: (v) {
              cfg.patternDiameter = v.clamp(3.0, 40.0);
              widget.viewModel.updateToolConfig();
            },
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Expanded(
                child: _chip('Ø6 mm', cfg.patternDiameter == 6.0, () {
                  cfg.patternDiameter = 6.0;
                  widget.viewModel.updateToolConfig();
                }),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: _chip('Ø8 mm', cfg.patternDiameter == 8.0, () {
                  cfg.patternDiameter = 8.0;
                  widget.viewModel.updateToolConfig();
                }),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: _chip('Ø10 mm', cfg.patternDiameter == 10.0, () {
                  cfg.patternDiameter = 10.0;
                  widget.viewModel.updateToolConfig();
                }),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: _chip('Ø12 mm', cfg.patternDiameter == 12.0, () {
                  cfg.patternDiameter = 12.0;
                  widget.viewModel.updateToolConfig();
                }),
              ),
            ],
          ),
        ] else if (cfg.patternHoleType == PunchType.square) ...[
          _doubleInput(
            label: 'Square Size (S)',
            val: cfg.patternSquareSize,
            step: 1.0,
            fractionDigits: 0,
            onChanged: (v) {
              cfg.patternSquareSize = v.clamp(4.0, 40.0);
              widget.viewModel.updateToolConfig();
            },
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Expanded(
                child: _chip('8×8 mm', cfg.patternSquareSize == 8.0, () {
                  cfg.patternSquareSize = 8.0;
                  widget.viewModel.updateToolConfig();
                }),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: _chip('10×10 mm', cfg.patternSquareSize == 10.0, () {
                  cfg.patternSquareSize = 10.0;
                  widget.viewModel.updateToolConfig();
                }),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: _chip('12×12 mm', cfg.patternSquareSize == 12.0, () {
                  cfg.patternSquareSize = 12.0;
                  widget.viewModel.updateToolConfig();
                }),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: _chip('15×15 mm', cfg.patternSquareSize == 15.0, () {
                  cfg.patternSquareSize = 15.0;
                  widget.viewModel.updateToolConfig();
                }),
              ),
            ],
          ),
        ] else if (cfg.patternHoleType == PunchType.rectangle) ...[
          Row(
            children: [
              Expanded(
                child: _doubleInput(
                  label: 'Length (L)',
                  val: cfg.patternRectWidth,
                  step: 1.0,
                  fractionDigits: 0,
                  onChanged: (v) {
                    cfg.patternRectWidth = v.clamp(8.0, 80.0);
                    widget.viewModel.updateToolConfig();
                  },
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _doubleInput(
                  label: 'Width (W)',
                  val: cfg.patternRectHeight,
                  step: 1.0,
                  fractionDigits: 0,
                  onChanged: (v) {
                    cfg.patternRectHeight = v.clamp(4.0, 40.0);
                    widget.viewModel.updateToolConfig();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Expanded(
                child: _chip('20×10', cfg.patternRectWidth == 20.0 && cfg.patternRectHeight == 10.0, () {
                  cfg.patternRectWidth = 20.0;
                  cfg.patternRectHeight = 10.0;
                  widget.viewModel.updateToolConfig();
                }),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: _chip('25×12', cfg.patternRectWidth == 25.0 && cfg.patternRectHeight == 12.0, () {
                  cfg.patternRectWidth = 25.0;
                  cfg.patternRectHeight = 12.0;
                  widget.viewModel.updateToolConfig();
                }),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: _chip('30×15', cfg.patternRectWidth == 30.0 && cfg.patternRectHeight == 15.0, () {
                  cfg.patternRectWidth = 30.0;
                  cfg.patternRectHeight = 15.0;
                  widget.viewModel.updateToolConfig();
                }),
              ),
            ],
          ),
        ],
        const SizedBox(height: 5),

        // 3. Mode toggle: Staggered vs Straight
        Row(
          children: [
            Expanded(
              child: _chip('Staggered (SS5)', cfg.patternStaggered, () {
                cfg.patternStaggered = true;
                widget.viewModel.updateToolConfig();
              }),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _chip('Straight Grid', !cfg.patternStaggered, () {
                cfg.patternStaggered = false;
                widget.viewModel.updateToolConfig();
              }),
            ),
          ],
        ),
        const SizedBox(height: 4),

        // 4. Grid counts
        Row(
          children: [
            Expanded(
              child: _numInput(
                label: 'Cols (X)',
                val: cfg.patternColsX,
                onChanged: (v) {
                  cfg.patternColsX = v.clamp(1, 15);
                  widget.viewModel.updateToolConfig();
                },
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _numInput(
                label: 'Rows (Y)',
                val: cfg.patternRowsY,
                onChanged: (v) {
                  cfg.patternRowsY = v.clamp(1, 60);
                  widget.viewModel.updateToolConfig();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),

        // 5. Pitches (Both Pitch X and Pitch Y editable)
        Row(
          children: [
            Expanded(
              child: _doubleInput(
                label: 'Pitch X',
                val: cfg.patternPitchX,
                step: 5.0,
                fractionDigits: 0,
                onChanged: (v) {
                  cfg.patternPitchX = v.clamp(15.0, 200.0);
                  widget.viewModel.updateToolConfig();
                },
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _doubleInput(
                label: 'Pitch Y',
                val: cfg.patternPitchY,
                step: 5.0,
                fractionDigits: 0,
                onChanged: (v) {
                  cfg.patternPitchY = v.clamp(20.0, 250.0);
                  widget.viewModel.updateToolConfig();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // 6. Interactive Rotation Dial
        RotationDialWidget(
          angleDeg: cfg.patternRotationDeg,
          onAngleChanged: (deg) {
            cfg.patternRotationDeg = deg;
            widget.viewModel.updateToolConfig();
          },
          label: 'Manual Hole Rotation',
        ),
        const SizedBox(height: 6),

        // 7. Auto-Perforate Floor Button
        SizedBox(
          width: double.infinity,
          height: 24,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.bolt, size: 12),
            label: const Text('Auto-Perforate Floor', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
              foregroundColor: Colors.white,
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            onPressed: () {
              widget.viewModel.applyPerforationToActiveFloor();
              widget.viewModel.setToolMode(StudioToolMode.select);
            },
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Other Tool Bodies (Bend/Flange, Round, Obround, Square, Chamfer)
  // ---------------------------------------------------------------------------
  Widget _buildBendFlangeBody() {
    final vm = widget.viewModel;
    final isFlange = vm.toolMode == StudioToolMode.addFlange;
    final isAuto = vm.autoBendPlacementEnabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: isAuto ? const Color(0xFFF0FDF4) : const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: isAuto ? const Color(0xFF86EFAC) : const Color(0xFFFDE68A),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      isAuto ? Icons.auto_awesome : Icons.edit_note,
                      size: 15,
                      color: isAuto ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isAuto ? 'Automatic Snapping: ON' : 'Manual Drawing: ON',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isAuto ? const Color(0xFF166534) : const Color(0xFF92400E),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const Text(
                            'Press [Ctrl] key once to toggle',
                            style: TextStyle(fontSize: 8.5, color: Color(0xFF64748B)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Transform.scale(
                scale: 0.75,
                child: Switch(
                  value: isAuto,
                  activeThumbColor: const Color(0xFF16A34A),
                  onChanged: (val) => vm.toggleAutoBendPlacement(enabled: val),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isFlange
              ? '• Click near boundary to auto-project return flange.\n• Or click-and-drag 2 points for custom orientation.'
              : '• Click near notch/edge to auto-detect fold bend line.\n• Or click-and-drag 2 points for custom bend line.',
          style: const TextStyle(fontSize: 9, color: Color(0xFF475569), height: 1.3),
        ),
      ],
    );
  }

  Widget _buildRoundHoleBody(ActiveToolConfig cfg) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'HOLE DIAMETER',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 8.5, fontWeight: FontWeight.bold),
            ),
            CadNumberSpinner(
              value: cfg.roundHoleDiameter,
              min: 1.0,
              max: 250.0,
              step: 0.5,
              decimals: 1,
              suffix: 'mm',
              width: 95,
              onChanged: (val) {
                cfg.roundHoleDiameter = val;
                widget.viewModel.updateToolConfig();
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'STANDARD CLEARANCE PUNCHES',
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 7.5, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 3),
        Wrap(
          spacing: 3,
          runSpacing: 3,
          children: [
            _chip('M3 (3.4)', (cfg.roundHoleDiameter - 3.4).abs() < 0.1, () {
              cfg.roundHoleDiameter = 3.4;
              widget.viewModel.updateToolConfig();
            }),
            _chip('M4 (4.5)', (cfg.roundHoleDiameter - 4.5).abs() < 0.1, () {
              cfg.roundHoleDiameter = 4.5;
              widget.viewModel.updateToolConfig();
            }),
            _chip('M5 (5.5)', (cfg.roundHoleDiameter - 5.5).abs() < 0.1, () {
              cfg.roundHoleDiameter = 5.5;
              widget.viewModel.updateToolConfig();
            }),
            _chip('M6 (6.6)', (cfg.roundHoleDiameter - 6.6).abs() < 0.1, () {
              cfg.roundHoleDiameter = 6.6;
              widget.viewModel.updateToolConfig();
            }),
            _chip('M8 (9.0)', (cfg.roundHoleDiameter - 9.0).abs() < 0.1, () {
              cfg.roundHoleDiameter = 9.0;
              widget.viewModel.updateToolConfig();
            }),
            _chip('M10 (11.0)', (cfg.roundHoleDiameter - 11.0).abs() < 0.1, () {
              cfg.roundHoleDiameter = 11.0;
              widget.viewModel.updateToolConfig();
            }),
            _chip('1/4" (6.4)', (cfg.roundHoleDiameter - 6.35).abs() < 0.15, () {
              cfg.roundHoleDiameter = 6.35;
              widget.viewModel.updateToolConfig();
            }),
            _chip('1/2" (12.7)', (cfg.roundHoleDiameter - 12.7).abs() < 0.15, () {
              cfg.roundHoleDiameter = 12.7;
              widget.viewModel.updateToolConfig();
            }),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Single click stamps preset. Drag draws custom diameter.',
          style: TextStyle(color: Color(0xFF64748B), fontSize: 8),
        ),
      ],
    );
  }

  Widget _buildObroundSlotBody(ActiveToolConfig cfg) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('SLOT SIZE', style: TextStyle(color: Color(0xFF64748B), fontSize: 8, fontWeight: FontWeight.bold)),
            Text('${cfg.obroundWidth.round()} × ${cfg.obroundLength.round()} mm',
                style: const TextStyle(color: Color(0xFF0284C7), fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: _chip('30×7 (Tray)', (cfg.obroundWidth - 30.0).abs() < 0.1, () {
                cfg.obroundWidth = 30.0;
                cfg.obroundLength = 7.0;
                widget.viewModel.updateToolConfig();
              }),
            ),
            Expanded(
              child: _chip('25×7', (cfg.obroundWidth - 25.0).abs() < 0.1, () {
                cfg.obroundWidth = 25.0;
                cfg.obroundLength = 7.0;
                widget.viewModel.updateToolConfig();
              }),
            ),
            Expanded(
              child: _chip('20×6', (cfg.obroundWidth - 20.0).abs() < 0.1, () {
                cfg.obroundWidth = 20.0;
                cfg.obroundLength = 6.0;
                widget.viewModel.updateToolConfig();
              }),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSquareBody(ActiveToolConfig cfg) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'SIZE MODIFIER',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 8.5, fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                const Text('1:1 Square', style: TextStyle(fontSize: 8, color: Color(0xFF64748B))),
                const SizedBox(width: 2),
                InkWell(
                  onTap: () {
                    cfg.squareAspectLocked = !cfg.squareAspectLocked;
                    if (cfg.squareAspectLocked) {
                      cfg.rectHeight = cfg.squareSize;
                      cfg.rectWidth = cfg.squareSize;
                    }
                    widget.viewModel.updateToolConfig();
                  },
                  child: Icon(
                    cfg.squareAspectLocked ? Icons.lock_outline : Icons.lock_open_outlined,
                    size: 13,
                    color: cfg.squareAspectLocked ? const Color(0xFF0284C7) : const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (cfg.squareAspectLocked) ...[
          CadNumberSpinner(
            label: 'Square Size (W = H)',
            value: cfg.squareSize,
            min: 2.0,
            max: 500.0,
            step: 1.0,
            decimals: 1,
            suffix: 'mm',
            onChanged: (val) {
              cfg.squareSize = val;
              cfg.rectWidth = val;
              cfg.rectHeight = val;
              widget.viewModel.updateToolConfig();
            },
          ),
        ] else ...[
          Row(
            children: [
              Expanded(
                child: CadNumberSpinner(
                  label: 'Width',
                  value: cfg.rectWidth,
                  min: 2.0,
                  max: 500.0,
                  step: 1.0,
                  decimals: 1,
                  suffix: 'mm',
                  onChanged: (val) {
                    cfg.rectWidth = val;
                    widget.viewModel.updateToolConfig();
                  },
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: CadNumberSpinner(
                  label: 'Height',
                  value: cfg.rectHeight,
                  min: 2.0,
                  max: 500.0,
                  step: 1.0,
                  decimals: 1,
                  suffix: 'mm',
                  onChanged: (val) {
                    cfg.rectHeight = val;
                    widget.viewModel.updateToolConfig();
                  },
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 6),
        const Text(
          'STANDARD SQUARE PUNCHES',
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 7.5, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 3),
        Wrap(
          spacing: 3,
          runSpacing: 3,
          children: [10.0, 15.0, 20.0, 25.0, 30.0, 50.0].map((s) {
            final active = cfg.squareAspectLocked && (cfg.squareSize - s).abs() < 0.1;
            return _chip('${s.round()}×${s.round()}', active, () {
              cfg.squareSize = s;
              cfg.rectWidth = s;
              cfg.rectHeight = s;
              cfg.squareAspectLocked = true;
              widget.viewModel.updateToolConfig();
            });
          }).toList(),
        ),
        const SizedBox(height: 6),
        const Text(
          'Single click stamps preset. Drag draws custom rectangle.',
          style: TextStyle(color: Color(0xFF64748B), fontSize: 8),
        ),
      ],
    );
  }

  Widget _buildChamferBody(ActiveToolConfig cfg) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('CHAMFER DIST', style: TextStyle(color: Color(0xFF64748B), fontSize: 8, fontWeight: FontWeight.bold)),
            Text('${cfg.chamferDist.toStringAsFixed(1)} mm',
                style: const TextStyle(color: Color(0xFF0284C7), fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [5.0, 10.0, 15.0, 20.0].map((c) {
            final active = (cfg.chamferDist - c).abs() < 0.1;
            return Expanded(
              child: _chip('${c.round()}mm', active, () {
                cfg.chamferDist = c;
                widget.viewModel.updateToolConfig();
              }),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _tabButton(String label, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 3),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 8,
              fontWeight: active ? FontWeight.bold : FontWeight.w500,
              color: active ? const Color(0xFF0284C7) : const Color(0xFF64748B),
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(String text, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 1),
        padding: const EdgeInsets.symmetric(vertical: 3),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFE0F2FE) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: active ? const Color(0xFF0284C7) : const Color(0xFFE2E8F0)),
        ),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              color: active ? const Color(0xFF0284C7) : const Color(0xFF475569),
              fontSize: 8,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _numInput({required String label, required int val, required ValueChanged<int> onChanged}) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF64748B), fontSize: 7)),
          Row(
            children: [
              InkWell(
                onTap: () => onChanged(val - 1),
                child: const Icon(Icons.remove, size: 10, color: Color(0xFF64748B)),
              ),
              Expanded(
                child: Center(
                  child: Text('$val', style: const TextStyle(color: Color(0xFF0284C7), fontSize: 9, fontWeight: FontWeight.bold)),
                ),
              ),
              InkWell(
                onTap: () => onChanged(val + 1),
                child: const Icon(Icons.add, size: 10, color: Color(0xFF0284C7)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _doubleInput({
    required String label,
    required double val,
    required double step,
    required ValueChanged<double> onChanged,
    int fractionDigits = 1,
  }) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF64748B), fontSize: 7, fontWeight: FontWeight.w600)),
          Row(
            children: [
              InkWell(
                onTap: () => onChanged(val - step),
                child: const Icon(Icons.remove, size: 10, color: Color(0xFF64748B)),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    fractionDigits == 0 ? '${val.round()}' : val.toStringAsFixed(fractionDigits),
                    style: const TextStyle(color: Color(0xFF0284C7), fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              InkWell(
                onTap: () => onChanged(val + step),
                child: const Icon(Icons.add, size: 10, color: Color(0xFF0284C7)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
