// =============================================================================
// parts_tree_panel.dart
//
// Interactive CAD Feature & Parts Tree Panel for Sheet Metal Studio.
// Displays the hierarchical model structure:
// - Part Root & Physical Properties (Material, Thickness, Net/Gross Weight)
// - Planar Faces (Centroids, Dimensions, Roles, Anchor status)
// - Press-Brake Bends (Angles, Radii, CAM Violations, Collision Badges)
// - Perforation Patterns (Grouped arrays, expandable child holes, exclusion)
// - Standalone CNC Punches (Round, Slot, Rectangle, Coordinates)
// - Laser Cut Lines / Slits
// - Press Brake Machine CAM Tooling & Auto-Sequencing
//
// Clicking any entity selects it across 2D & 3D viewports and opens its properties.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../engine/bend_sequence_engine.dart';
import '../../models/dsf_document.dart';
import '../../viewmodels/sheet_metal_studio_viewmodel.dart';
import '../../models/planar_sheet_face.dart';
import '../../models/cnc_punch_primitive.dart';
import '../../models/perforation_pattern.dart';
import '../../models/press_brake_machine.dart';
import '../../models/press_brake_punch_catalog.dart';
import '../../engine/press_brake_cam_engine.dart';
import '../../models/cad_feature.dart';
import '../../models/fold_bend_line.dart';
import 'punch_tooling_selector_dialog.dart';

class PartsTreePanel extends StatefulWidget {
  final SheetMetalStudioViewModel viewModel;
  final VoidCallback? onClose;

  const PartsTreePanel({super.key, required this.viewModel, this.onClose});

  @override
  State<PartsTreePanel> createState() => _PartsTreePanelState();
}

class _PartsTreePanelState extends State<PartsTreePanel> {
  bool _expandFeatureTree = false;
  bool _expandFaces = true;
  bool _expandBends = true;
  bool _expandPatterns = true;
  bool _expandPunches = true;
  bool _expandCuts = true;
  bool _expandMachine = true;
  final Set<String> _expandedPatternIds = {};
  DateTime? _lastClickTime;
  String? _lastClickKey;

  void _handleItemClick({
    required String key,
    required VoidCallback onTap,
    VoidCallback? onDoubleTap,
  }) {
    final now = DateTime.now();
    final isDouble = _lastClickKey == key &&
        _lastClickTime != null &&
        now.difference(_lastClickTime!).inMilliseconds < 450;
    _lastClickTime = now;
    _lastClickKey = key;
    onTap();
    if (isDouble && onDoubleTap != null) {
      onDoubleTap();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final doc = widget.viewModel.document;
        final violations = widget.viewModel.bendViolations;
        final seqReport = widget.viewModel.bendSequenceReport;

        return Container(
          width: 270,
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              right: BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x06000000),
                blurRadius: 4,
                offset: Offset(2, 0),
              ),
            ],
          ),
          child: Column(
            children: [
              // 1. Header with Close Button
              _buildHeader(),

              // 2. Part Summary Card (Material, Net/Gross Weight)
              // 2. Ultra-compact Part & Material Meta Bar
              _buildPartSummaryCard(doc),

              // 3. Scrollable Tree Hierarchy (compact vertical layout)
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  children: [
                    // 0. Unified CAD Feature Tree (Step 11 #24 - Features with CAM badges)
                    _buildCadFeatureTreeSection(doc, violations, seqReport),

                    const SizedBox(height: 2),

                    // A. Faces Group
                    _buildFacesSection(doc),

                    const SizedBox(height: 2),

                    // B. Bends & Flanges Group
                    _buildBendsAndFlangesSection(doc, violations, seqReport),

                    const SizedBox(height: 2),

                    // C. Perforation Patterns Group (Unified array entities)
                    if (doc.perforationPatterns.isNotEmpty) ...[
                      _buildPatternsSection(doc),
                      const SizedBox(height: 2),
                    ],

                    // D. Standalone Punches Group
                    _buildPunchesSection(doc),

                    const SizedBox(height: 2),

                    // E. Cut Lines Group
                    if (doc.cutLines.isNotEmpty) ...[
                      _buildCutsSection(doc),
                      const SizedBox(height: 2),
                    ],

                    // F. Press Brake CAM Machine & Sequence Config
                    _buildMachineSection(seqReport),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1)),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_tree, size: 14, color: Color(0xFF0284C7)),
          const SizedBox(width: 6),
          const Expanded(
            child: Text(
              'PARTS TREE',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.6,
                color: Color(0xFF0F172A),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (widget.onClose != null)
            IconButton(
              icon: const Icon(
                Icons.chevron_left,
                size: 18,
                color: Color(0xFF0284C7),
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              onPressed: widget.onClose,
              tooltip: 'Collapse Tree Panel (<)',
            ),
        ],
      ),
    );
  }

  Widget _buildCadFeatureTreeSection(
    DsfDocument doc,
    Map<String, BendValidationResult> violations,
    BendSequenceReport seqReport,
  ) {
    final features = widget.viewModel.featureTree;
    final selectedBendId = widget.viewModel.selectedBendId;
    final selectedFaceId = widget.viewModel.selectedFaceId;
    final selectedPatternId = widget.viewModel.selectedPatternId;
    final selectedPunchId = widget.viewModel.selectedPunchId;
    final selectedCutId = widget.viewModel.selectedCutId;

    return _buildSectionHeader(
      title: 'CAD Feature Tree',
      count: features.length,
      icon: Icons.alt_route,
      isExpanded: _expandFeatureTree,
      onToggle: () => setState(() => _expandFeatureTree = !_expandFeatureTree),
      children: [
        for (final feat in features)
          Builder(
            builder: (context) {
              bool isSelected = false;
              IconData icon = Icons.circle;
              Color iconColor = const Color(0xFF64748B);
              String subtitle = '';
              Widget? badge;

              if (feat is SheetBaseFeature) {
                isSelected = selectedFaceId == feat.faceId;
                icon = Icons.crop_portrait;
                iconColor = const Color(0xFF0284C7);
                subtitle = '${feat.areaMm2.toStringAsFixed(0)} mm²';
              } else if (feat is SheetBendFeature) {
                isSelected = selectedBendId == feat.bendLineId;
                if (feat.isFlange) {
                  icon = Icons.border_top;
                  iconColor = const Color(0xFF8B5CF6);
                  subtitle = 'FLANGE ${feat.angleDeg.toStringAsFixed(0)}° ${feat.direction.toUpperCase()} | R${feat.radiusMm.toStringAsFixed(1)}';
                } else {
                  icon = Icons.change_history;
                  iconColor = feat.direction == 'up' ? const Color(0xFF0284C7) : const Color(0xFFD97706);
                  subtitle = 'BEND ${feat.angleDeg.toStringAsFixed(0)}° ${feat.direction.toUpperCase()} | R${feat.radiusMm.toStringAsFixed(1)} | K=${feat.kFactor.toStringAsFixed(2)}';
                }

                final vResult = violations[feat.bendLineId];
                final hasCAMViolation = vResult != null && !vResult.isClean;
                final stepInfo = seqReport.stepForBend(feat.bendLineId);
                final hasCollision = stepInfo?.hasCollision ?? false;

                if (hasCAMViolation || hasCollision) {
                  badge = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasCAMViolation)
                        Tooltip(
                          message: vResult.violations.map((v) => v.message).join('\n'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(color: const Color(0xFFF59E0B), width: 0.8),
                            ),
                            child: const Text(
                              '⚠️ CAM',
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFB45309),
                              ),
                            ),
                          ),
                        ),
                      if (hasCollision) ...[
                        const SizedBox(width: 4),
                        Tooltip(
                          message: stepInfo?.reason ?? 'Tooling collision risk in sequence',
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(color: const Color(0xFFEF4444), width: 0.8),
                            ),
                            child: const Text(
                              '💥 COLLISION',
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFDC2626),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                }
              } else if (feat is SheetPatternFeature) {
                isSelected = selectedPatternId == feat.patternId;
                icon = Icons.grid_view;
                iconColor = const Color(0xFF0D9488);
                subtitle = '${feat.countX}×${feat.countY} Array (${feat.holeType})';
              } else if (feat is SheetHoleFeature) {
                isSelected = selectedPunchId == feat.punchId;
                icon = Icons.circle_outlined;
                iconColor = const Color(0xFF0284C7);
                subtitle = '(${feat.x.toStringAsFixed(0)}, ${feat.y.toStringAsFixed(0)})';
              } else if (feat is SheetCutoutFeature) {
                isSelected = selectedCutId == feat.cutId;
                icon = Icons.content_cut;
                iconColor = const Color(0xFFE11D48);
                subtitle = 'L: ${feat.lengthMm.toStringAsFixed(0)} mm';
              } else if (feat is SheetReliefFeature) {
                icon = Icons.rounded_corner;
                iconColor = const Color(0xFF8B5CF6);
                subtitle = '${feat.reliefType} (${feat.widthMm.toStringAsFixed(1)}×${feat.depthMm.toStringAsFixed(1)}mm)';
              }

              VoidCallback? onDelete;
              if (feat is SheetPatternFeature) {
                onDelete = () => widget.viewModel.deletePattern(feat.patternId);
              } else if (feat is SheetHoleFeature) {
                onDelete = () => widget.viewModel.deletePunch(feat.punchId);
              } else if (feat is SheetCutoutFeature) {
                onDelete = () => widget.viewModel.deleteCutLine(feat.cutId);
              }

              return _buildTreeRow(
                id: feat.id,
                isSelected: isSelected,
                icon: icon,
                iconColor: iconColor,
                title: feat.name,
                subtitle: subtitle.isNotEmpty ? subtitle : null,
                badge: badge,
                isVisible: feat.isVisible,
                onVisibilityToggle: () => widget.viewModel.toggleFeatureSuppression(feat),
                onDelete: onDelete,
                onTap: () => widget.viewModel.selectFeature(feat),
                onDoubleTap: () {
                  widget.viewModel.selectFeature(feat);
                  widget.viewModel.setPropertyInspectorOpen(true);
                },
              );
            },
          ),
      ],
    );
  }

  Widget _buildPartSummaryCard(DsfDocument doc) {
    final gradeText = doc.material.materialGrade.isNotEmpty
        ? doc.material.materialGrade
        : doc.material.materialType.shortCode;
    final finishText = doc.material.finish.code;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.architecture,
                size: 12,
                color: Color(0xFF0284C7),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  doc.itemName.isNotEmpty ? doc.itemName : 'Sheet Blank',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                'Net: ${doc.netWeightKg.toStringAsFixed(2)} kg',
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0284C7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Mat: $gradeText • Finish: $finishText',
                  style: const TextStyle(
                    fontSize: 9,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'Gross: ${doc.grossWeightKg.toStringAsFixed(2)} kg',
                style: const TextStyle(fontSize: 8.5, color: Color(0xFF94A3B8)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- 1. Faces Section ---
  Widget _buildFacesSection(DsfDocument doc) {
    return _buildSectionHeader(
      title: 'Planar Faces',
      count: doc.faces.length,
      icon: Icons.crop_portrait,
      isExpanded: _expandFaces,
      onToggle: () => setState(() => _expandFaces = !_expandFaces),
      children: [
        for (final face in doc.faces) ...[
          () {
            final appliedPatterns = doc.perforationPatterns
                .where((p) => p.targetFaceId == face.id)
                .toList();

            return _buildTreeRow(
              id: face.id,
              isSelected: widget.viewModel.selectedFaceId == face.id,
              icon: face.isBaseAnchor ? Icons.anchor : Icons.square_foot,
              iconColor: face.isBaseAnchor
                  ? const Color(0xFF0284C7)
                  : const Color(0xFF64748B),
              title: '${face.id}: ${_formatFaceRole(face.role)}',
              subtitle: '${face.areaMm2.toStringAsFixed(0)} mm²',
              badge: appliedPatterns.isNotEmpty
                  ? Tooltip(
                      message:
                          '${appliedPatterns.length} Perforation Pattern(s) Applied',
                      child: InkWell(
                        onTap: () {
                          widget.viewModel
                              .selectPattern(appliedPatterns.first.id);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFCCFBF1),
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(
                              color: const Color(0xFF0D9488),
                              width: 0.6,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.grid_view,
                                size: 10,
                                color: Color(0xFF0D9488),
                              ),
                              const SizedBox(width: 2),
                              Text(
                                '${appliedPatterns.length}',
                                style: const TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F766E),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : null,
              isVisible: face.isVisible,
              onVisibilityToggle: () =>
                  widget.viewModel.toggleFaceVisibility(face.id),
              onTap: () => widget.viewModel.selectFace(face.id),
              onDoubleTap: () {
                widget.viewModel.selectFace(face.id);
                widget.viewModel.setPropertyInspectorOpen(true);
              },
            );
          }(),
        ],
      ],
    );
  }

  // --- 2. Bends & Flanges Section ---
  Widget _buildBendsAndFlangesSection(
    DsfDocument doc,
    Map<String, BendValidationResult> violations,
    BendSequenceReport seqReport,
  ) {
    return _buildSectionHeader(
      title: 'Bends & Flanges',
      count: doc.bends.length,
      icon: Icons.polyline,
      isExpanded: _expandBends,
      onToggle: () => setState(() => _expandBends = !_expandBends),
      children: [
        if (doc.bends.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: Text(
              'No bend or flange lines',
              style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
            ),
          ),
        for (final b in doc.bends)
          _buildTreeRow(
            id: b.id,
            isSelected: widget.viewModel.selectedBendId == b.id,
            icon: b.isFlange ? Icons.border_top : Icons.change_history,
            iconColor: b.isFlange
                ? const Color(0xFF8B5CF6)
                : (b.direction == BendDirection.up
                    ? const Color(0xFF0284C7)
                    : const Color(0xFFD97706)),
            title: '${b.isFlange ? "Flange" : "Bend"} ${b.id}',
            subtitle:
                '${b.targetAngleDeg.toStringAsFixed(0)}° ${b.direction == BendDirection.up ? "↑" : "↓"} | R${b.radiusMm.toStringAsFixed(1)}',
            isVisible: b.isVisible,
            onVisibilityToggle: () =>
                widget.viewModel.toggleBendVisibility(b.id),
            onDelete: () => widget.viewModel.deleteBendLine(b.id),
            onTap: () => widget.viewModel.selectBend(b.id),
            onDoubleTap: () {
              widget.viewModel.selectBend(b.id);
              widget.viewModel.setPropertyInspectorOpen(true);
            },
          ),
      ],
    );
  }

  // --- 3. Perforation Patterns Section ---
  Widget _buildPatternsSection(DsfDocument doc) {
    return _buildSectionHeader(
      title: 'Perforation Groups',
      count: doc.perforationPatterns.length,
      icon: Icons.grid_view,
      isExpanded: _expandPatterns,
      onToggle: () => setState(() => _expandPatterns = !_expandPatterns),
      children: [
        for (final pat in doc.perforationPatterns) ...[
          _buildPatternGroupRow(pat),
        ],
      ],
    );
  }

  Widget _buildPatternGroupRow(PerforationPattern pat) {
    final isExpanded = _expandedPatternIds.contains(pat.id);
    final isSelected =
        widget.viewModel.selectedPatternId == pat.id &&
        widget.viewModel.selectedPatternHoleIndex == null;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFE0F2FE) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isSelected ? const Color(0xFF0284C7) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Row(
              children: [
                InkWell(
                  onTap: () => setState(() {
                    if (isExpanded) {
                      _expandedPatternIds.remove(pat.id);
                    } else {
                      _expandedPatternIds.add(pat.id);
                    }
                  }),
                  child: Icon(
                    isExpanded ? Icons.expand_more : Icons.chevron_right,
                    size: 16,
                    color: const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.grid_on,
                  size: 14,
                  color: pat.isVisible
                      ? const Color(0xFF0D9488)
                      : const Color(0xFF94A3B8),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: InkWell(
                    onTap: () => _handleItemClick(
                      key: 'pattern_${pat.id}',
                      onTap: () => widget.viewModel.selectPattern(pat.id),
                      onDoubleTap: () {
                        widget.viewModel.selectPattern(pat.id);
                        widget.viewModel.setPropertyInspectorOpen(true);
                      },
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${pat.id} (${pat.countX}×${pat.countY})',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: pat.isVisible
                                ? const Color(0xFF0F172A)
                                : const Color(0xFF94A3B8),
                            decoration: pat.isVisible
                                ? null
                                : TextDecoration.lineThrough,
                          ),
                        ),
                        Text(
                          '${pat.activeHoleCount} holes | ${pat.slotWidthMm.toStringAsFixed(0)}×${pat.slotLengthMm.toStringAsFixed(0)}mm',
                          style: TextStyle(
                            fontSize: 9,
                            color: pat.isVisible
                                ? const Color(0xFF64748B)
                                : const Color(0xFFCBD5E1),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                      pat.isVisible ? Icons.visibility : Icons.visibility_off,
                      size: 14,
                      color: pat.isVisible
                          ? const Color(0xFF0284C7)
                          : const Color(0xFF94A3B8),
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 22,
                      minHeight: 22,
                    ),
                    onPressed: () =>
                        widget.viewModel.togglePatternVisibility(pat.id),
                    tooltip: pat.isVisible
                        ? 'Hide / Suppress Group (Temporary Delete)'
                        : 'Show / Unsuppress Group',
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 14,
                      color: Color(0xFFEF4444),
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 22,
                      minHeight: 22,
                    ),
                    onPressed: () => widget.viewModel.deletePattern(pat.id),
                    tooltip: 'Delete Group',
                  ),
                ],
              ),
            ),
          if (isExpanded) ...[
            Container(
              padding: const EdgeInsets.only(left: 20, right: 6, bottom: 6),
              child: Column(
                children: [
                  for (int idx = 0; idx < pat.totalHoleCount; idx++) ...[
                    if (!pat.deletedHoleIndices.contains(idx)) ...[
                      Builder(
                        builder: (context) {
                          final isHoleSelected =
                              widget.viewModel.selectedPatternId == pat.id &&
                              widget.viewModel.selectedPatternHoleIndex == idx;
                          final center = pat.holeCenter(idx);

                          return InkWell(
                            onTap: () => _handleItemClick(
                              key: 'pattern_${pat.id}_hole_$idx',
                              onTap: () =>
                                  widget.viewModel.selectPattern(pat.id, idx),
                              onDoubleTap: () {
                                widget.viewModel.selectPattern(pat.id, idx);
                                widget.viewModel.setPropertyInspectorOpen(true);
                              },
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: isHoleSelected
                                    ? const Color(0xFFBAE6FD)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.circle,
                                    size: 8,
                                    color: Color(0xFF0D9488),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Hole #$idx (${center.x.toStringAsFixed(0)}, ${center.y.toStringAsFixed(0)})',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFF334155),
                                    ),
                                  ),
                                  const Spacer(),
                                  InkWell(
                                    onTap: () => widget.viewModel
                                        .deletePatternHole(pat.id, idx),
                                    child: const Icon(
                                      Icons.close,
                                      size: 12,
                                      color: Color(0xFF94A3B8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --- 4. Punches Section ---
  Widget _buildPunchesSection(DsfDocument doc) {
    return _buildSectionHeader(
      title: 'Individual Punches',
      count: doc.punches.length,
      icon: Icons.adjust,
      isExpanded: _expandPunches,
      onToggle: () => setState(() => _expandPunches = !_expandPunches),
      children: [
        if (doc.punches.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: Text(
              'No individual punches',
              style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
            ),
          ),
        for (final p in doc.punches)
          _buildTreeRow(
            id: p.id,
            isSelected: widget.viewModel.selectedPunchId == p.id,
            icon: p.type == PunchType.roundHole
                ? Icons.circle_outlined
                : (p.type == PunchType.ellipse
                    ? Icons.egg_outlined
                    : Icons.crop_7_5),
            iconColor: const Color(0xFF0284C7),
            title: '${p.id}: ${_formatPunchType(p.type)}',
            subtitle:
                '(${p.center.x.toStringAsFixed(0)}, ${p.center.y.toStringAsFixed(0)})',
            isVisible: p.isVisible,
            onVisibilityToggle: () =>
                widget.viewModel.togglePunchVisibility(p.id),
            onDelete: () => widget.viewModel.deletePunch(p.id),
            onTap: () => widget.viewModel.selectPunch(p.id),
            onDoubleTap: () {
              widget.viewModel.selectPunch(p.id);
              widget.viewModel.setPropertyInspectorOpen(true);
            },
          ),
      ],
    );
  }

  // --- 5. Cut Lines Section ---
  Widget _buildCutsSection(DsfDocument doc) {
    return _buildSectionHeader(
      title: 'Laser Cut Slits',
      count: doc.cutLines.length,
      icon: Icons.content_cut,
      isExpanded: _expandCuts,
      onToggle: () => setState(() => _expandCuts = !_expandCuts),
      children: [
        for (final c in doc.cutLines)
          _buildTreeRow(
            id: c.id,
            isSelected: widget.viewModel.selectedCutId == c.id,
            icon: Icons.horizontal_rule,
            iconColor: const Color(0xFFE11D48),
            title: '${c.id}: Cut Slit',
            subtitle: 'L: ${c.length.toStringAsFixed(0)}mm',
            onDelete: () => widget.viewModel.deleteCutLine(c.id),
            onTap: () => widget.viewModel.selectCut(c.id),
            onDoubleTap: () {
              widget.viewModel.selectCut(c.id);
              widget.viewModel.setPropertyInspectorOpen(true);
            },
          ),
      ],
    );
  }

  // --- 6. Press Brake Machine & CAM Config Section ---
  Widget _buildMachineSection(BendSequenceReport seqReport) {
    return _buildSectionHeader(
      title: 'Press Brake CAM',
      icon: Icons.precision_manufacturing,
      isExpanded: _expandMachine,
      onToggle: () => setState(() => _expandMachine = !_expandMachine),
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Machine Preset:',
                style: TextStyle(fontSize: 10, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 4),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value:
                      PressBrakeMachine.standardPresets().any(
                        (m) => m.id == widget.viewModel.selectedMachine.id,
                      )
                      ? widget.viewModel.selectedMachine.id
                      : PressBrakeMachine.standardPresets().first.id,
                  isDense: true,
                  isExpanded: true,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w600,
                  ),
                  items: [
                    for (final m in PressBrakeMachine.standardPresets())
                      DropdownMenuItem(
                        value: m.id,
                        child: Text(m.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (id) {
                    if (id != null) {
                      final base = PressBrakeMachine.standardPresets()
                          .firstWhere((m) => m.id == id);
                      widget.viewModel.setSelectedMachine(
                        base.copyWith(
                          punchType: widget.viewModel.selectedMachine.punchType,
                        ),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(height: 8),
              // Punch Tool Profile Banner with SVG Thumbnail & Change button
              Builder(
                builder: (context) {
                  final punchProfile = PressBrakePunchProfile.getForType(
                    widget.viewModel.selectedMachine.punchType,
                  );
                  return Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 44,
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: SvgPicture.string(punchProfile.svgString),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                punchProfile.name,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F172A),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${punchProfile.standardCode} (${punchProfile.tipAngleDeg.toStringAsFixed(0)}°)',
                                style: const TextStyle(
                                  fontSize: 8.5,
                                  color: Color(0xFF0284C7),
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.swap_horiz,
                            size: 16,
                            color: Color(0xFF0284C7),
                          ),
                          tooltip: 'Select Punch Tool from Catalog',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 26,
                            minHeight: 26,
                          ),
                          onPressed: () => PunchToolingSelectorDialog.show(
                            context,
                            widget.viewModel,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      'V-Die: ${widget.viewModel.selectedMachine.vDieWidthMm.toStringAsFixed(0)}mm',
                      style: const TextStyle(
                        fontSize: 9.5,
                        color: Color(0xFF64748B),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      'Max: ${widget.viewModel.selectedMachine.maxTonnageTons.toStringAsFixed(0)}T',
                      style: const TextStyle(
                        fontSize: 9.5,
                        color: Color(0xFF64748B),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Auto-Sequence Bends Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.auto_fix_high, size: 14),
                  label: const Text(
                    'Auto-Sequence Bends',
                    style: TextStyle(fontSize: 11),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  onPressed: () => widget.viewModel.autoSequenceBends(),
                ),
              ),
              const SizedBox(height: 6),
              // Step Mode Toggle Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: Icon(
                    widget.viewModel.isStepMode
                        ? Icons.view_timeline
                        : Icons.tune,
                    size: 14,
                    color: widget.viewModel.isStepMode
                        ? const Color(0xFF059669)
                        : const Color(0xFF64748B),
                  ),
                  label: Text(
                    widget.viewModel.isStepMode
                        ? 'Step-by-Step Active'
                        : 'Enable Step Mode',
                    style: TextStyle(
                      fontSize: 11,
                      color: widget.viewModel.isStepMode
                          ? const Color(0xFF059669)
                          : const Color(0xFF334155),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  onPressed: () => widget.viewModel.toggleStepMode(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- Helper UI Components ---

  Widget _buildSectionHeader({
    required String title,
    int? count,
    required IconData icon,
    required bool isExpanded,
    required VoidCallback onToggle,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(3),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
            child: Row(
              children: [
                Icon(
                  isExpanded ? Icons.remove : Icons.add,
                  size: 13,
                  color: const Color(0xFF64748B),
                ),
                const SizedBox(width: 3),
                Icon(icon, size: 12, color: const Color(0xFF0284C7)),
                const SizedBox(width: 4),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF334155),
                          ),
                        ),
                      ),
                      if (count != null) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 0.5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '$count',
                            style: const TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (isExpanded)
          Padding(
            padding: const EdgeInsets.only(left: 6, top: 1),
            child: Column(children: children),
          ),
      ],
    );
  }

  Widget _buildTreeRow({
    required String id,
    required bool isSelected,
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    Widget? badge,
    bool isVisible = true,
    VoidCallback? onVisibilityToggle,
    VoidCallback? onDelete,
    required VoidCallback onTap,
    VoidCallback? onDoubleTap,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      margin: const EdgeInsets.symmetric(vertical: 0.5),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFE0F2FE) : Colors.transparent,
        borderRadius: BorderRadius.circular(3),
        border: isSelected
            ? Border.all(color: const Color(0xFF0284C7), width: 1)
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _handleItemClick(
                key: id,
                onTap: onTap,
                onDoubleTap: onDoubleTap,
              ),
              borderRadius: BorderRadius.circular(3),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 11,
                    color: isVisible ? iconColor : const Color(0xFF94A3B8),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.1,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.w500,
                      color: !isVisible
                          ? const Color(0xFF94A3B8)
                          : (isSelected
                              ? const Color(0xFF0284C7)
                              : const Color(0xFF0F172A)),
                      decoration:
                          isVisible ? null : TextDecoration.lineThrough,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 8.5,
                        height: 1.1,
                        color: isVisible
                            ? const Color(0xFF64748B)
                            : const Color(0xFFCBD5E1),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
            if (badge != null) ...[const SizedBox(width: 3), badge],
            if (onVisibilityToggle != null) ...[
              const SizedBox(width: 2),
              IconButton(
                icon: Icon(
                  isVisible ? Icons.visibility : Icons.visibility_off,
                  size: 11,
                  color: isVisible
                      ? const Color(0xFF0284C7)
                      : const Color(0xFF94A3B8),
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                onPressed: onVisibilityToggle,
                tooltip: isVisible
                    ? 'Hide / Suppress (Temporary Delete)'
                    : 'Show / Unsuppress',
              ),
            ],
            if (onDelete != null) ...[
              const SizedBox(width: 2),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  size: 12,
                  color: Color(0xFFEF4444),
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                onPressed: onDelete,
                tooltip: 'Delete',
              ),
            ],
          ],
        ),
      );
  }

  String _formatFaceRole(FaceRole role) {
    switch (role) {
      case FaceRole.baseFloor:
        return 'Base Floor (Anchor)';
      case FaceRole.sideWall:
        return 'Side Wall';
      case FaceRole.returnFlange:
        return 'Return Flange';
      case FaceRole.mountingTab:
        return 'Mounting Tab';
      case FaceRole.coverPanel:
        return 'Cover Panel';
      case FaceRole.custom:
        return 'Planar Panel';
    }
  }

  String _formatPunchType(PunchType type) {
    switch (type) {
      case PunchType.roundHole:
        return 'Round Hole';
      case PunchType.obroundSlot:
        return 'Obround Slot';
      case PunchType.ellipse:
        return 'Ellipse';
      case PunchType.square:
        return 'Square';
      case PunchType.rectangle:
        return 'Rectangle';
      case PunchType.cluster:
        return 'Cluster Punch';
      case PunchType.compound:
        return 'Compound Punch';
    }
  }
}
