import '../../engine/constraints/dependency_graph_engine.dart';
// =============================================================================
// pattern_property_sheet.dart
//
// Floating On-Canvas Property Inspector for selected Perforation Pattern groups.
// Allows live parametric modification:
// - Target Face Selection & Automatic Re-Nesting Recalculation
// - Hole Type (Obround Slot, Round Hole, Square, Rectangle)
// - Hole Dimensions (Length, Width, Diameter)
// - Array Grid Spacing (Pitch X, Pitch Y)
// - Staggering (Alternating row offset)
// - Live Rotation
// - Part Suppression / Temporary Delete (Hides in 2D & 3D mesh)
// - Hole exclusion and dimension label toggles
// - Apply Changes & Cancel Changes buttons with draft rollback
// =============================================================================

import 'package:flutter/material.dart';
import '../../engine/cnc_turret_engine.dart';
import '../../models/cnc_punch_primitive.dart';
import '../../models/perforation_pattern.dart';
import '../../models/planar_sheet_face.dart';
import '../../viewmodels/sheet_metal_studio_viewmodel.dart';

class PatternPropertySheet extends StatefulWidget {
  final SheetMetalStudioViewModel viewModel;
  final PerforationPattern pattern;
  final int? selectedHoleIndex;
  final bool isCollapsed;
  final VoidCallback? onToggleCollapse;
  final VoidCallback? onClose;
  final GestureDragStartCallback? onDragStartHeader;
  final GestureDragUpdateCallback? onDragHeader;

  const PatternPropertySheet({
    super.key,
    required this.viewModel,
    required this.pattern,
    this.selectedHoleIndex,
    this.isCollapsed = false,
    this.onToggleCollapse,
    this.onClose,
    this.onDragStartHeader,
    this.onDragHeader,
  });

  @override
  State<PatternPropertySheet> createState() => _PatternPropertySheetState();
}

class _PatternPropertySheetState extends State<PatternPropertySheet> {
  late PerforationPattern _initialPattern;
  late PerforationPattern _draftPattern;
  bool _hasChanges = false;
  bool _showFormulaCounts = false;
  bool _showFormulaPitches = false;

  @override
  void initState() {
    super.initState();
    _initialPattern = widget.pattern;
    _draftPattern = widget.pattern;
  }

  @override
  void didUpdateWidget(covariant PatternPropertySheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pattern.id != widget.pattern.id) {
      _initialPattern = widget.pattern;
      _draftPattern = widget.pattern;
      _hasChanges = false;
    } else if (!_hasChanges && oldWidget.pattern != widget.pattern) {
      _initialPattern = widget.pattern;
      _draftPattern = widget.pattern;
    }
  }

  void _updateDraft(PerforationPattern newDraft) {
    setState(() {
      _draftPattern = newDraft;
      _hasChanges = true;
    });
    // Live update on canvas so the user sees preview interactively
    widget.viewModel.replacePattern(_draftPattern);
  }

  void _applyChanges() {
    setState(() {
      _initialPattern = _draftPattern;
      _hasChanges = false;
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Applied changes to pattern ${_draftPattern.id}'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _cancelChanges() {
    widget.viewModel.replacePattern(_initialPattern);
    setState(() {
      _draftPattern = _initialPattern;
      _hasChanges = false;
    });
  }

  void _handleFaceChange(String newFaceId) {
    final faces = widget.viewModel.document.faces;
    final newFace = faces.cast<PlanarSheetFace?>().firstWhere(
      (f) => f?.id == newFaceId,
      orElse: () => null,
    );
    if (newFace == null || newFace.vertices.length < 3) return;

    final reNested = CncTurretEngine.autoNestPerforationOnFace(
      face: newFace,
      doc: widget.viewModel.document,
      holeType: _draftPattern.holeType,
      slotWidth: _draftPattern.slotWidthMm,
      slotLength: _draftPattern.slotLengthMm,
      diameterMm: _draftPattern.diameterMm,
      pitchY: _draftPattern.pitchY,
      overridePitchX: _draftPattern.pitchX,
      staggerDistance: _draftPattern.staggerDistanceMm,
      endMargin: 50.0,
      rotationDeg: _draftPattern.rotationDeg,
      staggered: _draftPattern.staggered,
      patternId: _draftPattern.id,
    );

    _updateDraft(
      reNested.copyWith(
        isVisible: _draftPattern.isVisible,
        showLabel: _draftPattern.showLabel,
      ),
    );
  }

  String _formatFaceRole(FaceRole role) {
    switch (role) {
      case FaceRole.baseFloor:
        return 'Base Floor';
      case FaceRole.sideWall:
        return 'Side Wall';
      case FaceRole.returnFlange:
        return 'Flange';
      case FaceRole.mountingTab:
        return 'Tab';
      case FaceRole.coverPanel:
        return 'Cover';
      case FaceRole.custom:
        return 'Panel';
    }
  }

  @override
  Widget build(BuildContext context) {
    const themeColor = Color(0xFF0D9488); // Teal for perforation patterns
    final pattern = _draftPattern;
    final faces = widget.viewModel.document.faces;
    final effectiveFaceId = pattern.targetFaceId ??
        (faces.isNotEmpty ? faces.first.id : null);

    return Container(
      width: 285.0,
      padding: const EdgeInsets.all(10.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(
          color: pattern.isVisible
              ? themeColor.withValues(alpha: 0.6)
              : const Color(0xFF94A3B8),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 16.0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header: Drag Handle + Title + Suppress Icon + Collapse + Close
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onPanStart: widget.onDragStartHeader,
                  onPanUpdate: widget.onDragHeader,
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      const Icon(Icons.drag_indicator, size: 14, color: Color(0xFF94A3B8)),
                      const SizedBox(width: 4),
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: pattern.isVisible ? themeColor : const Color(0xFF94A3B8),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${pattern.id} (PERF GROUP)',
                          style: TextStyle(
                            color: pattern.isVisible ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.6,
                            decoration: pattern.isVisible ? null : TextDecoration.lineThrough,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Quick Visibility / Suppress Toggle
              IconButton(
                icon: Icon(
                  pattern.isVisible ? Icons.visibility : Icons.visibility_off,
                  size: 16,
                  color: pattern.isVisible ? const Color(0xFF0284C7) : const Color(0xFF94A3B8),
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                onPressed: () {
                  _updateDraft(pattern.copyWith(isVisible: !pattern.isVisible));
                },
                tooltip: pattern.isVisible ? 'Hide / Suppress Part (Temp Delete)' : 'Show / Unsuppress Part',
              ),
              if (widget.onToggleCollapse != null) ...[
                InkWell(
                  onTap: widget.onToggleCollapse,
                  child: Icon(
                    widget.isCollapsed ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                    size: 18,
                    color: const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(width: 3),
              ],
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () {
                    if (_hasChanges) {
                      _cancelChanges();
                    }
                    widget.viewModel.selectPattern(null);
                    widget.onClose?.call();
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(4.0),
                    child: Icon(Icons.close, size: 16, color: Color(0xFF64748B)),
                  ),
                ),
              ),
            ],
          ),

          if (!widget.isCollapsed) ...[
            const Divider(height: 12.0, color: Color(0xFFE2E8F0)),

            // 1b. Target Surface / Planar Face Selector
            Row(
              children: [
                const Text(
                  'TARGET FACE',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 8.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFCBD5E1), width: 0.8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: faces.any((f) => f.id == effectiveFaceId) ? effectiveFaceId : null,
                        isDense: true,
                        isExpanded: true,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.w600,
                        ),
                        items: [
                          for (final f in faces)
                            DropdownMenuItem(
                              value: f.id,
                              child: Text(
                                '${f.id} (${_formatFaceRole(f.role)})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (newFid) {
                          if (newFid != null && newFid != effectiveFaceId) {
                            _handleFaceChange(newFid);
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8.0),

            // 2. Stats Row & Formula Expression Toggle
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        '${pattern.countX} Cols × ${pattern.countY} Rows',
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () => setState(() => _showFormulaCounts = !_showFormulaCounts),
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: (_showFormulaCounts || pattern.countXExpression != null)
                                ? const Color(0xFF0284C7).withValues(alpha: 0.15)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: (_showFormulaCounts || pattern.countXExpression != null)
                                  ? const Color(0xFF0284C7)
                                  : const Color(0xFFCBD5E1),
                              width: 0.8,
                            ),
                          ),
                          child: const Text(
                            'fx',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              fontStyle: FontStyle.italic,
                              color: Color(0xFF0284C7),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${pattern.activeHoleCount} / ${pattern.totalHoleCount} holes',
                  style: const TextStyle(fontSize: 10.5, color: Color(0xFF0284C7), fontWeight: FontWeight.w600),
                ),
              ],
            ),
            if (_showFormulaCounts || pattern.countXExpression != null) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F9FF),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFFBAE6FD), width: 0.8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('COL COUNT FORMULA (COUNT X)', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Color(0xFF0369A1))),
                    const SizedBox(height: 2),
                    TextFormField(
                      initialValue: pattern.countXExpression ?? '',
                      style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        hintText: 'e.g. floor((WIDTH - 40) / 25)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) {
                        final expr = val.trim().isEmpty ? null : val.trim();
                        final updated = pattern.copyWith(countXExpression: expr);
                        final evaluated = DependencyGraphEngine.evaluatePattern(updated, widget.viewModel.document.parameters);
                        _updateDraft(evaluated);
                      },
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 8.0),

            // 3. Hole Type Selector
            const Text(
              'HOLE TYPE',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 8.5, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: _chip('Slot', pattern.holeType == PunchType.obroundSlot, () {
                    _updateDraft(pattern.copyWith(holeType: PunchType.obroundSlot));
                  }),
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: _chip('Round', pattern.holeType == PunchType.roundHole, () {
                    _updateDraft(pattern.copyWith(holeType: PunchType.roundHole));
                  }),
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: _chip('Square', pattern.holeType == PunchType.square, () {
                    _updateDraft(pattern.copyWith(holeType: PunchType.square));
                  }),
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: _chip('Rect', pattern.holeType == PunchType.rectangle, () {
                    _updateDraft(pattern.copyWith(holeType: PunchType.rectangle));
                  }),
                ),
              ],
            ),

            const SizedBox(height: 8.0),

            // 4. Parametric Hole Dimensions
            const Text(
              'HOLE DIMENSIONS (MM)',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 8.5, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            if (pattern.holeType == PunchType.obroundSlot || pattern.holeType == PunchType.rectangle) ...[
              Row(
                children: [
                  Expanded(
                    child: _doubleInput(
                      label: 'Length (L)',
                      val: pattern.slotLengthMm,
                      step: 1.0,
                      fractionDigits: 0,
                      onChanged: (v) {
                        _updateDraft(pattern.copyWith(slotLengthMm: v.clamp(5.0, 150.0)));
                      },
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _doubleInput(
                      label: 'Width (W)',
                      val: pattern.slotWidthMm,
                      step: 0.5,
                      fractionDigits: 1,
                      onChanged: (v) {
                        _updateDraft(pattern.copyWith(slotWidthMm: v.clamp(2.0, 50.0)));
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: _chip('30×7 Std', pattern.slotLengthMm == 30.0 && pattern.slotWidthMm == 7.0, () {
                      _updateDraft(pattern.copyWith(slotLengthMm: 30.0, slotWidthMm: 7.0));
                    }),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: _chip('25×7 EN', pattern.slotLengthMm == 25.0 && pattern.slotWidthMm == 7.0, () {
                      _updateDraft(pattern.copyWith(slotLengthMm: 25.0, slotWidthMm: 7.0));
                    }),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: _chip('20×9 HD', pattern.slotLengthMm == 20.0 && pattern.slotWidthMm == 9.0, () {
                      _updateDraft(pattern.copyWith(slotLengthMm: 20.0, slotWidthMm: 9.0));
                    }),
                  ),
                ],
              ),
            ] else if (pattern.holeType == PunchType.roundHole) ...[
              _doubleInput(
                label: 'Diameter (Ø)',
                val: pattern.diameterMm,
                step: 0.5,
                fractionDigits: 1,
                onChanged: (v) {
                  _updateDraft(pattern.copyWith(diameterMm: v.clamp(2.0, 60.0)));
                },
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: _chip('Ø6', pattern.diameterMm == 6.0, () {
                      _updateDraft(pattern.copyWith(diameterMm: 6.0));
                    }),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: _chip('Ø8', pattern.diameterMm == 8.0, () {
                      _updateDraft(pattern.copyWith(diameterMm: 8.0));
                    }),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: _chip('Ø10', pattern.diameterMm == 10.0, () {
                      _updateDraft(pattern.copyWith(diameterMm: 10.0));
                    }),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: _chip('Ø12', pattern.diameterMm == 12.0, () {
                      _updateDraft(pattern.copyWith(diameterMm: 12.0));
                    }),
                  ),
                ],
              ),
            ] else if (pattern.holeType == PunchType.square) ...[
              _doubleInput(
                label: 'Square Size (S)',
                val: pattern.slotWidthMm,
                step: 1.0,
                fractionDigits: 0,
                onChanged: (v) {
                  _updateDraft(pattern.copyWith(
                    slotWidthMm: v.clamp(4.0, 50.0),
                    slotLengthMm: v.clamp(4.0, 50.0),
                  ));
                },
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: _chip('8×8', pattern.slotWidthMm == 8.0, () {
                      _updateDraft(pattern.copyWith(slotWidthMm: 8.0, slotLengthMm: 8.0));
                    }),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: _chip('10×10', pattern.slotWidthMm == 10.0, () {
                      _updateDraft(pattern.copyWith(slotWidthMm: 10.0, slotLengthMm: 10.0));
                    }),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: _chip('12×12', pattern.slotWidthMm == 12.0, () {
                      _updateDraft(pattern.copyWith(slotWidthMm: 12.0, slotLengthMm: 12.0));
                    }),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 8.0),

            // 5. Grid Pitches (Spacing) & Parameter Formula Toggle
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'GRID PITCH / SPACING (MM)',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 8.5, fontWeight: FontWeight.bold),
                ),
                InkWell(
                  onTap: () => setState(() => _showFormulaPitches = !_showFormulaPitches),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: (_showFormulaPitches || pattern.pitchXParameter != null)
                          ? const Color(0xFF0284C7).withValues(alpha: 0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: (_showFormulaPitches || pattern.pitchXParameter != null)
                            ? const Color(0xFF0284C7)
                            : const Color(0xFFCBD5E1),
                        width: 0.8,
                      ),
                    ),
                    child: const Text(
                      'fx',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        fontStyle: FontStyle.italic,
                        color: Color(0xFF0284C7),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_showFormulaPitches || pattern.pitchXParameter != null) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F9FF),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFFBAE6FD), width: 0.8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('PITCH X PARAMETER (OR FORMULA)', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Color(0xFF0369A1))),
                    const SizedBox(height: 2),
                    TextFormField(
                      initialValue: pattern.pitchXParameter ?? '',
                      style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        hintText: 'e.g. PITCH_X',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) {
                        final expr = val.trim().isEmpty ? null : val.trim();
                        final updated = pattern.copyWith(pitchXParameter: expr);
                        final evaluated = DependencyGraphEngine.evaluatePattern(updated, widget.viewModel.document.parameters);
                        _updateDraft(evaluated);
                      },
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: _doubleInput(
                    label: 'Pitch X (Cols)',
                    val: pattern.pitchX,
                    step: 5.0,
                    fractionDigits: 1,
                    onChanged: (v) {
                      _updateDraft(pattern.copyWith(pitchX: v.clamp(10.0, 300.0)));
                    },
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _doubleInput(
                    label: 'Pitch Y (Rows)',
                    val: pattern.pitchY,
                    step: 5.0,
                    fractionDigits: 1,
                    onChanged: (v) {
                      _updateDraft(pattern.copyWith(pitchY: v.clamp(10.0, 300.0)));
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8.0),

            // 6. Stagger & Rotation
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'Stagger Rows (50% Offset):',
                    style: TextStyle(fontSize: 10, color: Color(0xFF334155), fontWeight: FontWeight.w500),
                  ),
                ),
                Switch(
                  value: pattern.staggered,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (val) {
                    _updateDraft(pattern.copyWith(staggered: val));
                  },
                ),
              ],
            ),

            const SizedBox(height: 4.0),

            // Rotation Chips
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Rotation:', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                Text(
                  '${pattern.rotationDeg.toStringAsFixed(0)}°',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Wrap(
              spacing: 3.0,
              runSpacing: 2.0,
              children: [
                for (final deg in [0.0, 45.0, 90.0, 180.0]) ...[
                  ChoiceChip(
                    label: Text('${deg.toInt()}°', style: const TextStyle(fontSize: 9)),
                    selected: (pattern.rotationDeg - deg).abs() < 1e-3,
                    onSelected: (_) {
                      _updateDraft(pattern.copyWith(rotationDeg: deg));
                    },
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ],
            ),

            const SizedBox(height: 8.0),

            // 7. Tag Visibility
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'Dimension Tag:',
                    style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    pattern.showLabel ? Icons.visibility : Icons.visibility_off,
                    size: 16,
                    color: pattern.showLabel ? const Color(0xFF0284C7) : const Color(0xFF94A3B8),
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  splashRadius: 14,
                  tooltip: pattern.showLabel ? 'Hide Dimension Tag' : 'Show Dimension Tag',
                  onPressed: () {
                    _updateDraft(pattern.copyWith(showLabel: !pattern.showLabel));
                  },
                ),
              ],
            ),

            // 8. Selected Child Hole Actions
            if (widget.selectedHoleIndex != null) ...[
              const Divider(height: 10.0, color: Color(0xFFE2E8F0)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Selected Hole #${widget.selectedHoleIndex}',
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline, size: 14, color: Color(0xFFEF4444)),
                    label: const Text('Exclude Hole', style: TextStyle(fontSize: 10, color: Color(0xFFEF4444))),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                    onPressed: () {
                      widget.viewModel.deletePatternHole(pattern.id, widget.selectedHoleIndex!);
                    },
                  ),
                ],
              ),
            ],

            const Divider(height: 12.0, color: Color(0xFFE2E8F0)),

            // 9. Apply Changes & Cancel Changes Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check, size: 13),
                    label: const Text(
                      'Apply Changes',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _hasChanges ? const Color(0xFF0D9488) : const Color(0xFF94A3B8),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      elevation: _hasChanges ? 1 : 0,
                    ),
                    onPressed: _hasChanges ? _applyChanges : null,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.close, size: 13),
                    label: const Text(
                      'Cancel Changes',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _hasChanges ? const Color(0xFFEF4444) : const Color(0xFF94A3B8),
                      side: BorderSide(
                        color: _hasChanges ? const Color(0xFFFCA5A5) : const Color(0xFFE2E8F0),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                    ),
                    onPressed: _hasChanges ? _cancelChanges : null,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8.0),

            // 10. Delete Entire Pattern Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.delete_outline, size: 14, color: Color(0xFFEF4444)),
                label: const Text('Delete Perforation Group', style: TextStyle(fontSize: 10.5, color: Color(0xFFEF4444))),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFFCA5A5)),
                  padding: const EdgeInsets.symmetric(vertical: 5),
                ),
                onPressed: () => widget.viewModel.deleteSelectedPattern(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String label, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0D9488) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: isSelected ? const Color(0xFF0F766E) : const Color(0xFFCBD5E1),
            width: 0.8,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 8.5,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? Colors.white : const Color(0xFF334155),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
                    style: const TextStyle(color: Color(0xFF0284C7), fontSize: 9.5, fontWeight: FontWeight.bold),
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
