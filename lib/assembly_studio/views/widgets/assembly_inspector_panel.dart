import 'package:flutter/material.dart';

import '../../../sheet_metal_studio/models/cad_primitives.dart';
import '../../models/assembly_part.dart';
import '../../viewmodels/assembly_studio_viewmodel.dart';
import '../theme/assembly_studio_theme.dart';
import 'assembly_measurement_units_card.dart';

/// Dark GameStudio-style Property Grid Inspector panel.
/// Provides deep CAD inspection for Part Transform, 20mm Editable Flange, Micro-Nudge adjustments,
/// Sketched Face Features (Press 'S'), and Contact Welds. Uses dense 10px typography to maximize 3D canvas space.
class AssemblyInspectorPanel extends StatefulWidget {
  final AssemblyStudioViewModel viewModel;
  final double width;

  const AssemblyInspectorPanel({super.key, required this.viewModel, this.width = 265.0});

  @override
  State<AssemblyInspectorPanel> createState() => _AssemblyInspectorPanelState();
}

class _AssemblyInspectorPanelState extends State<AssemblyInspectorPanel> {
  final TextEditingController _searchCtrl = TextEditingController();
  final Set<String> _collapsedSections = {};
  String _filterQuery = '';

  AssemblyStudioTheme get theme => AssemblyStudioTheme(isLight: widget.viewModel.isLightBackground);

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() {
        _filterQuery = _searchCtrl.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggleSection(String sectionKey) {
    setState(() {
      if (_collapsedSections.contains(sectionKey)) {
        _collapsedSections.remove(sectionKey);
      } else {
        _collapsedSections.add(sectionKey);
      }
    });
  }

  bool _isSectionVisible(String sectionKey, String label) {
    if (_filterQuery.isEmpty) return true;
    return label.toLowerCase().contains(_filterQuery) || sectionKey.toLowerCase().contains(_filterQuery);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        final part = vm.selectedPart;
        final weld = vm.selectedWeld;
        final multiCount = vm.selectedPartIds.length;

        return Container(
          width: widget.width,
          decoration: BoxDecoration(
            color: theme.panelBackground, // Dynamic Light / Dark Property Grid
            border: Border(left: BorderSide(color: theme.panelBorder, width: 1.0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Header (Height 32px)
              Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: theme.panelHeaderBackground,
                  border: Border(bottom: BorderSide(color: theme.panelBorder, width: 1.0)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.tune_rounded, color: theme.accentSky, size: 14),
                    Flexible(
                      child: Text(
                        'PROPERTY GRID',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: theme.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Spacer(),
                    if (weld != null)
                      _buildHeaderBadge('WELD BEAD', const Color(0xFFF59E0B))
                    else if (multiCount > 1)
                      _buildHeaderBadge('$multiCount PARTS', theme.accentSky)
                    else if (part != null)
                      _buildHeaderBadge(
                        part.isComponentInstance ? 'COMPONENT' : part.type.name.toUpperCase(),
                        part.isComponentInstance ? const Color(0xFF818CF8) : const Color(0xFF34D399),
                      ),
                  ],
                ),
              ),

              // 2. Search Properties Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: theme.panelBackground,
                  border: Border(bottom: BorderSide(color: theme.panelBorder, width: 1.0)),
                ),
                child: Container(
                  height: 24,
                  decoration: BoxDecoration(
                    color: theme.inputBackground,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: theme.inputBorder, width: 0.8),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded, size: 12, color: theme.textTertiary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          style: TextStyle(fontSize: 10, color: theme.textPrimary),
                          cursorColor: theme.accentSky,
                          decoration: InputDecoration(
                            hintText: 'Search properties...',
                            hintStyle: TextStyle(fontSize: 9.5, color: theme.textMuted),
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      if (_filterQuery.isNotEmpty)
                        GestureDetector(
                          onTap: _searchCtrl.clear,
                          child: Icon(Icons.close_rounded, size: 11, color: theme.textTertiary),
                        ),
                    ],
                  ),
                ),
              ),

              // 3. Body
              Expanded(child: _buildBody(context, vm, part, weld, multiCount)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeaderBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AssemblyStudioViewModel vm, AssemblyPart? part, AssemblyWeldJoint? weld, int multiCount) {
    if (weld != null) {
      return _buildWeldInspector(vm, weld);
    }
    if (multiCount > 1) {
      return _buildMultiPartSelectionInspector(context, vm, vm.selectedParts);
    }
    if (part == null) {
      return _buildEmptyState(vm);
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      children: [
        // COMPONENT INSTANCE / DEFINITION CARD
        _buildComponentInstanceBanner(context, vm, part),
        const SizedBox(height: 6),

        // DIRECT 3D SKETCH ON MODEL BANNER (PRESS "S")
        _buildDrawSketchOnFaceBanner(context, vm, part),

        const SizedBox(height: 8),

        // TRANSFORM & NUDGE SECTION
        if (_isSectionVisible('transform', 'Transform Position Rotation'))
          _buildCollapsibleSection(key: 'transform', title: 'TRANSFORM & NUDGE', accentColor: const Color(0xFF38BDF8), child: _buildTransformSection(vm, part)),

        // DIMENSIONS & FLANGE SECTION
        if (_isSectionVisible('dimensions', 'Dimensions Length Flange Thickness Width Profile'))
          _buildCollapsibleSection(
            key: 'dimensions',
            title: 'SPECIFICATIONS & 20MM FLANGE',
            accentColor: const Color(0xFF10B981),
            child: _buildDimensionsSection(vm, part),
          ),

        // SEGMENTS & SPACING SECTION
        if (part.type == AssemblyPartType.straightRail || part.type == AssemblyPartType.bentRail)
          if (_isSectionVisible('segments', 'Segments Rung Spacing Pitch'))
            _buildCollapsibleSection(
              key: 'segments',
              title: 'LADDER STILE SEGMENTS',
              accentColor: const Color(0xFFFBBF24),
              child: _buildSegmentsSection(vm, part),
            ),

        // RUNGS SLOTS SECTION
        if (part.type == AssemblyPartType.rung)
          if (_isSectionVisible('slots', 'Slots Cable Tie Punch Web'))
            _buildCollapsibleSection(key: 'slots', title: 'CABLE-TIE SLOTS', accentColor: const Color(0xFF34D399), child: _buildRungSlotsSection(vm, part)),

        // SKETCHED FEATURES ON MODEL
        if (_isSectionVisible('sketches', 'Sketches Holes Cuts Face'))
          _buildCollapsibleSection(
            key: 'sketches',
            title: 'FACE SKETCHES (${part.sketches.length})',
            accentColor: const Color(0xFFA855F7),
            child: _buildSketchedFeaturesSection(context, vm, part),
          ),

        // JOINTS & BONDS
        if (_isSectionVisible('joints', 'Joints Welds Bonds Touching Auto-Weld'))
          _buildCollapsibleSection(
            key: 'joints',
            title: 'JOINTS & CONTACT WELDING',
            accentColor: const Color(0xFFF59E0B),
            child: _buildJoiningSection(vm, part),
          ),

        // GRAPHICS & MATERIAL FINISH (PBR SHADERS)
        if (_isSectionVisible('graphics', 'Graphics Materials Shaders PBR Finish'))
          _buildCollapsibleSection(
            key: 'graphics',
            title: 'SHADERS & GRAPHICS SETTINGS',
            accentColor: const Color(0xFF6366F1),
            child: _buildGraphicsSection(vm),
          ),

        // MEASUREMENT UNITS (SKETCHUP STYLE SS2)
        if (_isSectionVisible('units', 'Units Measurement Precision Length Snapping Angle Inches Feet Millimeters'))
          _buildCollapsibleSection(
            key: 'units',
            title: 'MEASUREMENT UNITS',
            accentColor: const Color(0xFF0284C7),
            child: AssemblyMeasurementUnitsCard(viewModel: vm),
          ),

        const SizedBox(height: 12),

        // Delete Part Button
        OutlinedButton.icon(
          icon: const Icon(Icons.delete_outline_rounded, size: 12, color: Color(0xFFEF4444)),
          label: const Text('Delete Part (Del)', style: TextStyle(fontSize: 9.5, color: Color(0xFFEF4444))),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 6),
            side: const BorderSide(color: Color(0xFFEF4444), width: 0.8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          onPressed: vm.deleteSelectedPart,
        ),
      ],
    );
  }

  Widget _buildEmptyState(AssemblyStudioViewModel vm) {
    final report = vm.evaluateLadderCompliance();
    final bom = vm.generateBillOfMaterials();

    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        const SizedBox(height: 8),
        Center(
          child: Column(
            children: const [
              Icon(Icons.touch_app_rounded, size: 28, color: Color(0xFF475569)),
              SizedBox(height: 6),
              Text(
                'No Part Selected',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
              ),
              SizedBox(height: 4),
              Text(
                'Click any part in the 3D viewport or Outliner tree to inspect properties and dimensions.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 8.5, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // OSHA & EN-ISO COMPLIANCE CARD
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.cardBackground,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: report.badgeColor.withValues(alpha: 0.5), width: 1.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(report.isCompliant ? Icons.verified_user_rounded : Icons.shield_rounded, size: 14, color: report.badgeColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'SAFETY COMPLIANCE',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: theme.textPrimary, letterSpacing: 0.3),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: report.badgeColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      report.overallStatus.name.toUpperCase(),
                      style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: report.badgeColor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text('Standards: OSHA 1910.23/28 & EN ISO 14122-4', style: TextStyle(fontSize: 8.5, color: theme.textTertiary)),
              const SizedBox(height: 4),
              Text(
                '${report.passCount} Pass • ${report.warnCount} Warning • ${report.failCount} Fail',
                style: TextStyle(fontSize: 9, color: theme.textSecondary, fontWeight: FontWeight.w600),
              ),
              if (!report.isCompliant) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                    icon: const Icon(Icons.auto_fix_high_rounded, size: 12),
                    label: const Text('Auto-Fix All Issues', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold)),
                    onPressed: vm.autoFixAllComplianceIssues,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),

        // BILL OF MATERIALS SUMMARY CARD
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.cardBackground,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: theme.accentSky.withValues(alpha: 0.4), width: 1.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.inventory_2_rounded, size: 14, color: theme.accentSky),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'BILL OF MATERIALS',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: theme.textPrimary, letterSpacing: 0.3),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text('Total Parts: ${bom.totalPartCount} pcs', style: TextStyle(fontSize: 8.5, color: theme.textSecondary)),
              const SizedBox(height: 2),
              Text('Total Weight: ${bom.totalWeightKg.toStringAsFixed(1)} kg', style: TextStyle(fontSize: 8.5, color: theme.textSecondary)),
              const SizedBox(height: 2),
              Text(
                'Weld Seams: ${bom.totalWeldCount} joints (${(bom.totalWeldLengthMm / 1000.0).toStringAsFixed(2)} m)',
                style: TextStyle(fontSize: 8.5, color: theme.textTertiary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // MEASUREMENT UNITS (SKETCHUP STYLE SS2)
        _buildCollapsibleSection(
          key: 'units',
          title: 'MEASUREMENT UNITS',
          accentColor: const Color(0xFF0284C7),
          child: AssemblyMeasurementUnitsCard(viewModel: vm),
        ),
      ],
    );
  }

  Widget _buildCollapsibleSection({required String key, required String title, required Color accentColor, required Widget child}) {
    final isCollapsed = _collapsedSections.contains(key);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: theme.cardBorder, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          InkWell(
            onTap: () => _toggleSection(key),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: theme.panelHeaderBackground,
                borderRadius: BorderRadius.vertical(top: const Radius.circular(4), bottom: Radius.circular(isCollapsed ? 4 : 0)),
                border: Border(left: BorderSide(color: accentColor, width: 2.5)),
              ),
              child: Row(
                children: [
                  Icon(isCollapsed ? Icons.arrow_right_rounded : Icons.arrow_drop_down_rounded, size: 13, color: theme.textTertiary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: theme.isLight ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Content
          if (!isCollapsed) Padding(padding: const EdgeInsets.all(8), child: child),
        ],
      ),
    );
  }

  // ===========================================================================
  // SECTION: COMPONENT INSTANCE & DEFINITIONS (SKETCHUP PARADIGM)
  // ===========================================================================
  Widget _buildComponentInstanceBanner(BuildContext context, AssemblyStudioViewModel vm, AssemblyPart part) {
    final isComp = part.isComponentInstance;
    final instanceCount = vm.getComponentInstanceCount(part.componentDefinitionId);

    if (isComp) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1B4B).withValues(alpha: 0.8), // Deep indigo
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: const Color(0xFF818CF8), width: 1.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, color: Color(0xFFA5B4FC), size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'COMPONENT ($instanceCount LINKED)',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: Color(0xFFE0E7FF)),
                  ),
                ),
                InkWell(
                  onTap: () => vm.makePartUnique(part.id),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4338CA),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF6366F1), width: 0.8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.link_off_rounded, color: Colors.white, size: 11),
                        SizedBox(width: 3),
                        Text(
                          'Make Unique',
                          style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text('Edits to dimensions, flange, & holes sync across all instances.', style: TextStyle(fontSize: 8.5, color: Color(0xFFC7D2FE))),
          ],
        ),
      );
    } else {
      // Standalone Part - Quick button to convert into component definition
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: theme.cardSurface,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: theme.borderSubtle, width: 0.8),
        ),
        child: Row(
          children: [
            Icon(Icons.widgets_outlined, color: theme.textMuted, size: 13),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Standalone Part', style: TextStyle(fontSize: 9.5, color: theme.textSecondary)),
            ),
            InkWell(
              onTap: () => vm.makePartComponent(part.id),
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                decoration: BoxDecoration(
                  color: theme.inputBackground,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: theme.borderSubtle, width: 0.8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome, color: Color(0xFF38BDF8), size: 10),
                    SizedBox(width: 3),
                    Text(
                      'Make Component',
                      style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w600, color: Color(0xFF38BDF8)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  // ===========================================================================
  // SECTION: DRAW ON FACE BANNER (KEY 'S')
  // ===========================================================================
  Widget _buildDrawSketchOnFaceBanner(BuildContext context, AssemblyStudioViewModel vm, AssemblyPart part) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF0369A1), Color(0xFF0284C7)]),
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: Row(
        children: [
          const Icon(Icons.draw_rounded, color: Colors.white, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'DIRECT 3D FACE SKETCH',
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                Text('Draw holes & slots directly on model faces', style: TextStyle(fontSize: 8, color: Color(0xFFE0F2FE))),
              ],
            ),
          ),
          InkWell(
            onTap: () {
              vm.focusPartAndEnterSketch(part.id);
            },
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text(
                    'SKETCH [S]',
                    style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Color(0xFF0369A1)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // SECTION: TRANSFORM & MICRO NUDGE
  // ===========================================================================
  Widget _buildTransformSection(AssemblyStudioViewModel vm, AssemblyPart part) {
    final step = vm.nudgeLinearStep;
    final rotStep = vm.nudgeAngularStep;
    final isBonded = vm.isPartBonded(part.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isBonded)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4), width: 0.8),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_rounded, size: 11, color: theme.accentRed),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'Position & rotation locked by weld joint.',
                    style: TextStyle(fontSize: 8.0, color: theme.isLight ? const Color(0xFF991B1B) : const Color(0xFFFCA5A5), fontWeight: FontWeight.w600),
                  ),
                ),
                InkWell(
                  onTap: () => vm.breakAllBondsForPart(part.id),
                  child: Text(
                    'Break',
                    style: TextStyle(fontSize: 8.0, color: theme.accentRed, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                  ),
                ),
              ],
            ),
          ),
        // Coordinates display
        Row(
          children: [
            _buildCoordBox('X', part.position.x, const Color(0xFFEF4444)),
            const SizedBox(width: 4),
            _buildCoordBox('Y', part.position.y, const Color(0xFF10B981)),
            const SizedBox(width: 4),
            _buildCoordBox('Z', part.position.z, const Color(0xFF38BDF8)),
          ],
        ),
        const SizedBox(height: 6),

        // Nudge Buttons (X, Y, Z)
        Row(
          children: [
            _buildMiniNudge('X-', () => vm.nudgeSelectedPosition(-step, 0, 0), const Color(0xFFEF4444)),
            const SizedBox(width: 3),
            _buildMiniNudge('X+', () => vm.nudgeSelectedPosition(step, 0, 0), const Color(0xFFEF4444)),
            const SizedBox(width: 5),
            _buildMiniNudge('Y-', () => vm.nudgeSelectedPosition(0, -step, 0), const Color(0xFF10B981)),
            const SizedBox(width: 3),
            _buildMiniNudge('Y+', () => vm.nudgeSelectedPosition(0, step, 0), const Color(0xFF10B981)),
            const SizedBox(width: 5),
            _buildMiniNudge('Z-', () => vm.nudgeSelectedPosition(0, 0, -step), const Color(0xFF38BDF8)),
            const SizedBox(width: 3),
            _buildMiniNudge('Z+', () => vm.nudgeSelectedPosition(0, 0, step), const Color(0xFF38BDF8)),
          ],
        ),
        const SizedBox(height: 6),

        // Rotation & Step Selector
        Row(
          children: [
            _buildMiniNudge('Rx', () => vm.nudgeSelectedRotation(rotStep, 0, 0), const Color(0xFFF59E0B)),
            const SizedBox(width: 3),
            _buildMiniNudge('Ry', () => vm.nudgeSelectedRotation(0, rotStep, 0), const Color(0xFFF59E0B)),
            const SizedBox(width: 3),
            _buildMiniNudge('Rz 90°', () => vm.nudgeSelectedRotation(0, 0, 90), const Color(0xFFF59E0B)),
            const SizedBox(width: 5),
            // Step Dropdown
            PopupMenuButton<double>(
              tooltip: 'Step Size',
              itemBuilder: (ctx) => [0.5, 1.0, 5.0, 10.0, 50.0].map((s) {
                return PopupMenuItem(
                  value: s,
                  child: Text('±$s mm', style: const TextStyle(fontSize: 10)),
                );
              }).toList(),
              onSelected: vm.setNudgeLinearStep,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.inputBackground,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: theme.borderSubtle, width: 0.8),
                ),
                child: Text(
                  '±${step < 1 ? step.toStringAsFixed(1) : step.toInt()}mm',
                  style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCoordBox(String axis, double val, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2.5),
        decoration: BoxDecoration(
          color: theme.inputBackground,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: theme.inputBorder, width: 0.8),
        ),
        child: Row(
          children: [
            Text(
              axis,
              style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(width: 3),
            Expanded(
              child: Text(
                val.toInt().toString(),
                style: TextStyle(fontSize: 9, color: theme.textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniNudge(String label, VoidCallback onTap, Color color) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(3),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 3.5),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.cardBackground,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: color.withValues(alpha: 0.5), width: 0.8),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: color),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // SECTION: DIMENSIONS & 20MM FLANGE
  // ===========================================================================
  Widget _buildDimensionsSection(AssemblyStudioViewModel vm, AssemblyPart part) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Length
        if (part.type != AssemblyPartType.bentRail) ...[
          _buildDarkNumberRow(label: 'Length', val: part.length, unit: 'mm', step: 50, onChanged: vm.updateSelectedLength),
          const SizedBox(height: 5),
        ],

        // Web Height
        _buildDarkNumberRow(label: 'Web Height', val: part.height, unit: 'mm', step: 10, onChanged: vm.updateSelectedHeight),
        const SizedBox(height: 6),

        // EDITABLE 20MM FLANGE WIDTH (Highlighted feature)
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: theme.inputBackground,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.5), width: 0.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Flange Width',
                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: theme.accentSky),
                  ),
                  Text(
                    '${part.flangeWidth.toStringAsFixed(1)} mm',
                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: theme.textPrimary),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              // Preset pills: 15, 20mm default, 25, 30mm
              Row(
                children: [15.0, 20.0, 25.0, 30.0].map((fw) {
                  final isCurrent = (part.flangeWidth - fw).abs() < 0.1;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: InkWell(
                        onTap: () => vm.updateSelectedFlangeWidth(fw),
                        borderRadius: BorderRadius.circular(3),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isCurrent ? const Color(0xFF0284C7) : theme.cardSurface,
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(color: isCurrent ? const Color(0xFF0284C7) : theme.borderSubtle, width: 0.8),
                          ),
                          child: Text(
                            '${fw.toInt()}mm',
                            style: TextStyle(
                              fontSize: 8.5,
                              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                              color: isCurrent ? Colors.white : theme.textMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),

        // Thickness & Flange In/Out Orientation
        Row(
          children: [
            Expanded(
              child: _buildDarkNumberRow(label: 'Thk', val: part.thickness, unit: 'mm', step: 0.5, onChanged: vm.updateSelectedThickness),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: InkWell(
                onTap: vm.toggleSelectedFlangeOrientation,
                borderRadius: BorderRadius.circular(3),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.inputBackground,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: theme.borderSubtle, width: 0.8),
                  ),
                  child: Text(part.isFlangeOutward ? 'Flange Out' : 'Flange In', style: TextStyle(fontSize: 8.5, color: theme.textSecondary)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ===========================================================================
  // SECTION: LADDER SEGMENTS / RUNGS
  // ===========================================================================
  Widget _buildSegmentsSection(AssemblyStudioViewModel vm, AssemblyPart part) {
    if (part.type == AssemblyPartType.bentRail) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Arc Segments (${part.segments.length})', style: TextStyle(fontSize: 8.5, color: theme.textSecondary)),
              InkWell(
                onTap: () => vm.addSegmentToSelectedRail(),
                borderRadius: BorderRadius.circular(3),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(color: theme.accentSky.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(3)),
                  child: Text(
                    '+ Add Arc',
                    style: TextStyle(fontSize: 8, color: theme.accentSky, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...part.segments.asMap().entries.map((entry) {
            final idx = entry.key;
            final seg = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 2.5),
              child: Row(
                children: [
                  Text('Seg #${idx + 1}', style: TextStyle(fontSize: 8.5, color: theme.textMuted)),
                  const Spacer(),
                  Text('${seg.length.toInt()}mm @ ${seg.bendAngleDeg.toInt()}°', style: TextStyle(fontSize: 8.5, color: theme.textPrimary)),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () => vm.removeSegmentFromSelectedRail(idx),
                    child: const Icon(Icons.remove_circle_outline_rounded, size: 10, color: Color(0xFFEF4444)),
                  ),
                ],
              ),
            );
          }),
        ],
      );
    }

    // Straight Rail: Punched Rung Slots along Web
    final rungSlots = part.sketches.where((s) => s.isRungSlotEntity).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Rung Slots (${rungSlots.length} pcs)',
                style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: theme.textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            InkWell(
              onTap: () => vm.punchEvenRungSlots(part.id, count: 5),
              borderRadius: BorderRadius.circular(3),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.isLight ? const Color(0xFFFEF3C7) : const Color(0xFFFBBF24).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: const Color(0xFFD97706), width: 0.6),
                ),
                child: Text(
                  'Auto-Punch (5)',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: theme.isLight ? const Color(0xFFB45309) : const Color(0xFFFBBF24),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ...rungSlots.map(
          (s) => Padding(
            padding: const EdgeInsets.only(bottom: 2.0),
            child: Row(
              children: [
                const Icon(Icons.crop_portrait_rounded, size: 10, color: Color(0xFFD97706)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Slot @ ${s.distanceAlongRailMm.toInt()}mm',
                    style: TextStyle(fontSize: 8.5, color: theme.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  s.matedRungPartId != null ? 'Mated' : 'Open',
                  style: TextStyle(
                    fontSize: 7.5,
                    fontWeight: FontWeight.bold,
                    color: s.matedRungPartId != null ? (theme.isLight ? const Color(0xFF047857) : const Color(0xFF34D399)) : theme.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // SECTION: CABLE-TIE SLOTS
  // ===========================================================================
  Widget _buildRungSlotsSection(AssemblyStudioViewModel vm, AssemblyPart part) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Engineered C-Rung (40x20mm web profile).', style: TextStyle(fontSize: 8.5, color: theme.textTertiary)),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Orientation', style: TextStyle(fontSize: 8.5, color: theme.textSecondary)),
            InkWell(
              onTap: () => vm.toggleRungUpsideDown(part.id),
              borderRadius: BorderRadius.circular(3),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.inputBackground,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: theme.borderSubtle),
                ),
                child: Text(
                  part.isRungUpsideDown ? 'Upside Down (180°)' : 'Upright (0°)',
                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: theme.accentSky),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ===========================================================================
  // SECTION: SKETCHED FEATURES
  // ===========================================================================
  Widget _buildSketchedFeaturesSection(BuildContext context, AssemblyStudioViewModel vm, AssemblyPart part) {
    if (part.sketches.isEmpty) {
      return Row(
        children: [
          Icon(Icons.crop_free_rounded, size: 12, color: theme.textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'No features sketched. Press [S] to draw.',
              style: TextStyle(fontSize: 8.5, color: theme.textMuted),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: part.sketches.map((s) {
        final isHole = s.featureType == 'circle_hole';
        final isSlot = s.featureType == 'obround_slot' || s.featureType == 'rung_slot';
        final isBend = s.featureType == 'bend_line';
        final icon = isHole
            ? Icons.circle_outlined
            : (isSlot ? Icons.view_headline_rounded : (isBend ? Icons.linear_scale_rounded : Icons.crop_square_rounded));
        final col = isHole ? const Color(0xFF38BDF8) : (isSlot ? const Color(0xFF34D399) : const Color(0xFFFBBF24));
        final desc = isHole
            ? 'Hole Ø${s.widthMm.toInt()}mm'
            : (isSlot
                  ? '${s.isRungSlotEntity ? "Rung Slot" : "Slot"} ${s.widthMm.toInt()}x${s.heightMm.toInt()}mm'
                  : '${s.featureType} ${s.widthMm.toInt()}mm');

        return Padding(
          padding: const EdgeInsets.only(bottom: 3.0),
          child: Row(
            children: [
              Icon(icon, size: 10, color: col),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  desc,
                  style: TextStyle(fontSize: 8.5, color: theme.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Text('(${s.localCenter.x.toInt()}, ${s.localCenter.y.toInt()})', style: TextStyle(fontSize: 8, color: theme.textMuted)),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ===========================================================================
  // SECTION: JOINTS & WELDING
  // ===========================================================================
  Widget _buildJoiningSection(AssemblyStudioViewModel vm, AssemblyPart part) {
    final isBonded = vm.isPartBonded(part.id);
    final neighbors = vm.doc.parts.where((p) => part.weldedToPartIds.contains(p.id)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isBonded) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4), width: 0.8),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_rounded, size: 12, color: Color(0xFFEF4444)),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    '🔒 LOCKED BY WELD\nEntity cannot be moved or separated until weld is broken.',
                    style: TextStyle(
                      fontSize: 8.0,
                      height: 1.2,
                      color: theme.isLight ? const Color(0xFF991B1B) : const Color(0xFFFCA5A5),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: () => vm.breakAllBondsForPart(part.id),
            borderRadius: BorderRadius.circular(3),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              margin: const EdgeInsets.only(bottom: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: const Color(0xFFEF4444), width: 0.8),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.link_off_rounded, size: 11, color: Color(0xFFEF4444)),
                  SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      'Break Weld & Free Entity',
                      style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Color(0xFFEF4444)),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ] else
          const Padding(
            padding: EdgeInsets.only(bottom: 4.0),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline_rounded, size: 11, color: Color(0xFF10B981)),
                SizedBox(width: 4),
                Text(
                  'Independent Entity (Free to move & drag)',
                  style: TextStyle(fontSize: 8.5, color: Color(0xFF10B981), fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        if (neighbors.isNotEmpty) ...[
          ...neighbors.map(
            (n) => Padding(
              padding: const EdgeInsets.only(bottom: 3.0),
              child: Row(
                children: [
                  const Icon(Icons.flash_on_rounded, size: 10, color: Color(0xFFF59E0B)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Welded to ${n.name}',
                      style: TextStyle(fontSize: 8.5, color: theme.textSecondary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  InkWell(
                    onTap: () => vm.breakBond(part.id, n.id),
                    child: const Icon(Icons.link_off_rounded, size: 11, color: Color(0xFFEF4444)),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 4),
        InkWell(
          onTap: () => vm.setToolMode(SketchUpToolMode.weld),
          borderRadius: BorderRadius.circular(3),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF0284C7).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: const Color(0xFF0284C7), width: 0.8),
            ),
            child: Text(
              'Manual Weld Torch (W)',
              style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: theme.isLight ? const Color(0xFF0284C7) : const Color(0xFF38BDF8)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGraphicsSection(AssemblyStudioViewModel vm) {
    final prefs = vm.graphicsPreferences;
    final mat = prefs.materialSettings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'MATERIAL FINISH & PBR SHADER',
          style: TextStyle(fontSize: 8.0, color: theme.textMuted, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 3),
        Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: theme.inputBackground,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: theme.inputBorder, width: 0.8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<CadMaterialPresetType>(
              value: mat.preset,
              isExpanded: true,
              dropdownColor: theme.cardBackground,
              style: TextStyle(fontSize: 8.5, color: theme.textPrimary),
              items: CadMaterialPresetType.values.map((t) {
                return DropdownMenuItem(
                  value: t,
                  child: Text(t.label, style: TextStyle(fontSize: 8.5, color: theme.textPrimary)),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  vm.setMaterialPreset(val);
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '3D SHADING STYLE',
          style: TextStyle(fontSize: 8.0, color: theme.textMuted, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 3),
        Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: theme.inputBackground,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: theme.inputBorder, width: 0.8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<CadShadingStyle>(
              value: vm.shadingStyle,
              isExpanded: true,
              dropdownColor: theme.cardBackground,
              style: TextStyle(fontSize: 8.5, color: theme.textPrimary),
              items: CadShadingStyle.values.map((s) {
                return DropdownMenuItem(
                  value: s,
                  child: Text(s.label, style: TextStyle(fontSize: 8.5, color: theme.textPrimary)),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  vm.setShadingStyle(val);
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                'Ambient Occlusion',
                style: TextStyle(fontSize: 8.0, color: theme.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${prefs.ambientOcclusion.toInt()}%',
              style: TextStyle(fontSize: 8.0, color: theme.isLight ? const Color(0xFF0284C7) : const Color(0xFF38BDF8), fontWeight: FontWeight.bold),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context)
              .copyWith(trackHeight: 2, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4), overlayShape: SliderComponentShape.noOverlay),
          child: Slider(
            value: prefs.ambientOcclusion,
            min: 0,
            max: 100,
            activeColor: theme.isLight ? const Color(0xFF0284C7) : const Color(0xFF38BDF8),
            inactiveColor: theme.inputBorder,
            onChanged: (v) {
              vm.updateGraphicsPreferences((p) => p.copyWith(ambientOcclusion: v));
            },
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                'Shininess / Sheen',
                style: TextStyle(fontSize: 8.0, color: theme.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${prefs.shininess.toInt()}%',
              style: const TextStyle(fontSize: 8.0, color: Color(0xFFF59E0B), fontWeight: FontWeight.bold),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context)
              .copyWith(trackHeight: 2, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4), overlayShape: SliderComponentShape.noOverlay),
          child: Slider(
            value: prefs.shininess,
            min: 0,
            max: 100,
            activeColor: const Color(0xFFF59E0B),
            inactiveColor: theme.inputBorder,
            onChanged: (v) {
              vm.updateGraphicsPreferences((p) => p.copyWith(shininess: v));
            },
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // WELD JOINT INSPECTOR
  // ===========================================================================
  Widget _buildWeldInspector(AssemblyStudioViewModel vm, AssemblyWeldJoint weld) {
    final partA = vm.doc.parts.where((p) => p.id == weld.partAId).firstOrNull;
    final partB = vm.doc.parts.where((p) => p.id == weld.partBId).firstOrNull;

    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFFF59E0B), width: 0.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.flash_on_rounded, size: 14, color: Color(0xFFF59E0B)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '3D FILLET WELD BEAD',
                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: theme.textPrimary),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFFF59E0B).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                    child: Text(
                      weld.weldSymbol,
                      style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Color(0xFFF59E0B)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text('Spec: ${weld.standard}', style: TextStyle(fontSize: 8.5, color: theme.textMuted)),
              const SizedBox(height: 3),
              Text(
                'Type: ${weld.bothSides ? "Both-Sides Fillet (Dual Seams)" : "Single-Side Fillet"}',
                style: TextStyle(fontSize: 8.5, color: theme.isLight ? const Color(0xFF0284C7) : const Color(0xFF38BDF8)),
              ),
              const SizedBox(height: 3),
              Text(
                'Throat (t): ${weld.throatMm.toStringAsFixed(2)} mm (0.707 × a)',
                style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w600, color: Color(0xFF10B981)),
              ),
              const SizedBox(height: 3),
              Text('Connects: ${partA?.name ?? "Part A"} ↔ ${partB?.name ?? "Part B"}', style: TextStyle(fontSize: 8.5, color: theme.textSecondary)),
              const SizedBox(height: 3),
              Text(
                'Root XYZ: (${weld.weldPoint.x.toInt()}, ${weld.weldPoint.y.toInt()}, ${weld.weldPoint.z.toInt()}) mm',
                style: TextStyle(fontSize: 8, color: theme.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _buildDarkNumberRow(
          label: 'Bead Leg Size',
          val: weld.weldSizeMm,
          unit: 'mm',
          step: 1,
          onChanged: (v) {
            vm.updateSelectedWeldSize(v.clamp(1.0, 25.0));
          },
        ),
        const SizedBox(height: 6),
        _buildDarkNumberRow(
          label: 'Seam Length',
          val: weld.weldLengthMm,
          unit: 'mm',
          step: 5,
          onChanged: (v) {
            vm.updateSelectedWeldLength(v.clamp(10.0, 500.0));
          },
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          icon: const Icon(Icons.link_off_rounded, size: 12, color: Colors.white),
          label: const Text('Break Weld Bond (Del)', style: TextStyle(fontSize: 9.5, color: Colors.white)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFEF4444),
            padding: const EdgeInsets.symmetric(vertical: 7),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          onPressed: vm.deleteSelectedWeld,
        ),
      ],
    );
  }

  // ===========================================================================
  // MULTI-PART SELECTION INSPECTOR
  // ===========================================================================
  Widget _buildMultiPartSelectionInspector(BuildContext context, AssemblyStudioViewModel vm, List<AssemblyPart> parts) {
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF0284C7).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFF0284C7), width: 0.8),
          ),
          child: Text(
            'Multi-Selection: ${parts.length} parts selected',
            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: theme.isLight ? const Color(0xFF0369A1) : Colors.white),
          ),
        ),
        const SizedBox(height: 8),
        ...parts.map(
          (p) => Padding(
            padding: const EdgeInsets.only(bottom: 2.0),
            child: Text('• ${p.name}', style: TextStyle(fontSize: 8.5, color: theme.textSecondary)),
          ),
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          icon: const Icon(Icons.hardware_rounded, size: 12, color: Colors.white),
          label: const Text('Manual Weld Torch (W)', style: TextStyle(fontSize: 9.5, color: Colors.white)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0284C7),
            padding: const EdgeInsets.symmetric(vertical: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          onPressed: () => vm.setToolMode(SketchUpToolMode.weld),
        ),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          icon: const Icon(Icons.delete_outline_rounded, size: 12, color: Color(0xFFEF4444)),
          label: const Text('Delete Selection', style: TextStyle(fontSize: 9.5, color: Color(0xFFEF4444))),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 6),
            side: const BorderSide(color: Color(0xFFEF4444), width: 0.8),
          ),
          onPressed: vm.deleteSelectedPart,
        ),
      ],
    );
  }

  Widget _buildDarkNumberRow({
    required String label,
    required double val,
    required String unit,
    required double step,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: Text(label, style: TextStyle(fontSize: 8.5, color: theme.textSecondary)),
        ),
        InkWell(
          onTap: () => onChanged(val - step),
          borderRadius: BorderRadius.circular(2),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: theme.cardBackground,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: theme.cardBorder, width: 0.8),
            ),
            child: Icon(Icons.remove_rounded, size: 10, color: theme.textSecondary),
          ),
        ),
        const SizedBox(width: 4),
        Container(
          width: 45,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 2.5),
          decoration: BoxDecoration(
            color: theme.inputBackground,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: theme.inputBorder, width: 0.8),
          ),
          child: Text(
            val < 10 ? val.toStringAsFixed(1) : val.toInt().toString(),
            style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: theme.textPrimary),
          ),
        ),
        const SizedBox(width: 4),
        InkWell(
          onTap: () => onChanged(val + step),
          borderRadius: BorderRadius.circular(2),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: theme.cardBackground,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: theme.cardBorder, width: 0.8),
            ),
            child: Icon(Icons.add_rounded, size: 10, color: theme.textSecondary),
          ),
        ),
      ],
    );
  }
}
