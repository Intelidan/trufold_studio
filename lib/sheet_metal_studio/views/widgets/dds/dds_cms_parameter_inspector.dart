// =============================================================================
// dds_cms_parameter_inspector.dart
//
// Consolidated CMS Parameter Inspector Panel.
// Detachable, floating or dockable across both TruFold's Main CAD Window and
// the Technical Data Sheet (TDS) Studio.
//
// Features:
// 1. Dynamic product-aware port configuration:
//    - Unequal Cross: 4 ports (P1, P2, P3, P4)
//    - Equal Cross: 1 common port with unlink option
//    - Unequal Tee: Main Trunk (P1 & P2) + Branch (P3)
//    - Equal Tee: 1 common port
//    - Reducer: Inlet (P1) + Outlet (P2)
//    - Bends / Risers: Mouth W×H, Angle θ, Gusset Radius R
//    - Straight Tray: Width W, Height H, Length L
// 2. Coupler slots: Common length, width, pitch, and enable toggle.
// 3. Flange direction: Inside flange vs Outside return flange.
// 4. Flange sizes: Base flange size & Cover flange size with live cover mode.
// 5. Engineering bells & whistles: Gauge thickness, material, surface finish,
//    standard size quick presets, live physical takeoff HUD, and live CAD sync.
// =============================================================================

import 'package:flutter/material.dart';
import '../../../models/cms/cms_product_contract.dart';
import '../../../models/dds/dds_product_instance.dart';
import '../../../viewmodels/sheet_metal_studio_viewmodel.dart';

class DdsCmsParameterInspector extends StatefulWidget {
  final DdsProductInstance? instance;
  final ValueChanged<DdsProductInstance>? onInstanceChanged;
  final SheetMetalStudioViewModel? viewModel;
  final VoidCallback? onClose;
  final VoidCallback? onDetach;
  final bool isDetached;
  final bool isLightTheme;
  final void Function(DragStartDetails)? onDragStart;
  final void Function(DragUpdateDetails)? onDragUpdate;

  const DdsCmsParameterInspector({
    super.key,
    this.instance,
    this.onInstanceChanged,
    this.viewModel,
    this.onClose,
    this.onDetach,
    this.isDetached = false,
    this.isLightTheme = true,
    this.onDragStart,
    this.onDragUpdate,
  });

  @override
  State<DdsCmsParameterInspector> createState() => _DdsCmsParameterInspectorState();
}

class _DdsCmsParameterInspectorState extends State<DdsCmsParameterInspector> {
  late Map<String, TextEditingController> _controllers;
  bool _arePortsLinked = false;

  @override
  void initState() {
    super.initState();
    _controllers = {};
    if (widget.instance == null) {
      widget.viewModel?.addListener(_onViewModelChanged);
    }
    _syncControllers();
  }

  @override
  void didUpdateWidget(covariant DdsCmsParameterInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.instance == null) {
      if (oldWidget.viewModel != widget.viewModel) {
        oldWidget.viewModel?.removeListener(_onViewModelChanged);
        widget.viewModel?.addListener(_onViewModelChanged);
        _syncControllers();
      }
    } else {
      oldWidget.viewModel?.removeListener(_onViewModelChanged);
    }
    if (oldWidget.instance != widget.instance) {
      _syncControllers();
    }
  }

  @override
  void dispose() {
    widget.viewModel?.removeListener(_onViewModelChanged);
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _onViewModelChanged() {
    if (mounted) {
      setState(() {
        _syncControllers();
      });
    }
  }

  CmsProductContract? get _detectedContract {
    // 1. If an explicit TDS product instance is provided, it is completely authoritative
    if (widget.instance != null) {
      final tId = widget.instance!.templateReference.templateId.toLowerCase();
      final pType = widget.instance!.productName.toLowerCase();
      if (tId.contains('cross') || pType.contains('cross')) {
        return (tId.contains('unequal') || pType.contains('unequal')) ? CmsProductContract.unequalCross : CmsProductContract.equalCross;
      }
      if (tId.contains('tee') || pType.contains('tee')) {
        return (tId.contains('unequal') || pType.contains('unequal')) ? CmsProductContract.unequalTee : CmsProductContract.equalTee;
      }
      if (tId.contains('reducer') || pType.contains('reducer')) return CmsProductContract.straightReducer;
      if (tId.contains('inside_riser')) return CmsProductContract.insideRiser45;
      if (tId.contains('outside_riser')) return CmsProductContract.outsideRiser45;
      if (tId.contains('bend') || pType.contains('bend')) return tId.contains('90') ? CmsProductContract.bend90 : CmsProductContract.bend45;

      final params = widget.instance!.instanceParameters;
      if (params.containsKey('port4_width')) return CmsProductContract.unequalCross;
      if (params.containsKey('port3_width') || params.containsKey('branch_width')) return CmsProductContract.unequalTee;
      if (params.containsKey('port2_width') || params.containsKey('width2')) return CmsProductContract.straightReducer;
      return CmsProductContract.straightTray;
    }

    // 2. Otherwise fall back to Main CAD Window ViewModel
    final vm = widget.viewModel;
    if (vm != null) {
      if (vm.scalingController != null) {
        return vm.scalingController!.contract;
      }
      if (vm.cmsGuidedController.state.contract != null) {
        return vm.cmsGuidedController.state.contract;
      }
      final metaContract = vm.document.metadata['cms_product_contract'];
      if (metaContract is Map) {
        final c = CmsProductContract.lookup(metaContract['productType'] as String?, metaContract['variationName'] as String?);
        if (c != null) return c;
      }
      final cmsTemplate = vm.document.metadata['cmsTemplate'];
      if (cmsTemplate is Map) {
        final c = CmsProductContract.lookup(
          cmsTemplate['productType'] as String?,
          cmsTemplate['variation'] as String? ?? cmsTemplate['variationName'] as String?,
        );
        if (c != null) return c;
      }
      // Check physical ports from verifiedCmsPorts
      final ports = vm.verifiedCmsPorts;
      if (ports.length == 3) {
        final isUnequal = (ports[0].width - ports[1].width).abs() > 2 ||
            (ports[0].width - ports[2].width).abs() > 2 ||
            (ports[0].height - ports[1].height).abs() > 2 ||
            (ports[0].height - ports[2].height).abs() > 2;
        return isUnequal ? CmsProductContract.unequalTee : CmsProductContract.equalTee;
      } else if (ports.length == 4) {
        final isUnequal = ports.any((p) => (p.width - ports.first.width).abs() > 2 || (p.height - ports.first.height).abs() > 2);
        return isUnequal ? CmsProductContract.unequalCross : CmsProductContract.equalCross;
      } else if (ports.length == 2) {
        if ((ports[0].width - ports[1].width).abs() > 2 || (ports[0].height - ports[1].height).abs() > 2) {
          return CmsProductContract.straightReducer;
        }
      }
      final detected = vm.detectedFittingMetadata;
      if (detected != null) {
        final c = CmsProductContract.lookup(detected.product, detected.variantName);
        if (c != null) return c;
      }
      final lookupDoc = CmsProductContract.lookup(vm.document.productType, vm.document.itemName) ??
          CmsProductContract.lookup(null, vm.document.itemName) ??
          CmsProductContract.lookup(null, vm.document.productType);
      if (lookupDoc != null) return lookupDoc;
    }

    return null;
  }

  String get _productType {
    if (widget.instance != null) {
      final contract = _detectedContract;
      if (contract != null) {
        if (contract == CmsProductContract.unequalTee || contract.scalingProfile == CmsScalingProfile.unequalTee) return 'unequalTee';
        if (contract == CmsProductContract.equalTee || contract.scalingProfile == CmsScalingProfile.equalTee) return 'equalTee';
        if (contract == CmsProductContract.unequalCross || contract.scalingProfile == CmsScalingProfile.unequalCross) return 'unequalCross';
        if (contract == CmsProductContract.equalCross || contract.scalingProfile == CmsScalingProfile.equalCross) return 'equalCross';
        if (contract == CmsProductContract.straightReducer || contract.scalingProfile == CmsScalingProfile.reducer) return 'reducer';
        if (contract.scalingProfile == CmsScalingProfile.insideRiser) return 'insideRiser';
        if (contract.scalingProfile == CmsScalingProfile.outsideRiser) return 'outsideRiser';
        if (contract.scalingProfile == CmsScalingProfile.flatBend45) return 'flatBend45';
        if (contract.scalingProfile == CmsScalingProfile.flatBend90) return 'flatBend90';
      }
      final tId = widget.instance!.templateReference.templateId.toLowerCase();
      final pName = widget.instance!.productName.toLowerCase();
      if (tId.contains('cross') || pName.contains('cross')) return (tId.contains('unequal') || pName.contains('unequal')) ? 'unequalCross' : 'equalCross';
      if (tId.contains('tee') || pName.contains('tee')) return (tId.contains('unequal') || pName.contains('unequal')) ? 'unequalTee' : 'equalTee';
      if (tId.contains('reducer') || pName.contains('reducer')) return 'reducer';
      if (tId.contains('inside_riser')) return 'insideRiser';
      if (tId.contains('outside_riser')) return 'outsideRiser';
      if (tId.contains('bend') || pName.contains('bend')) return tId.contains('45') ? 'flatBend45' : 'flatBend90';
      final params = widget.instance!.instanceParameters;
      if (params.containsKey('port4_width')) return 'unequalCross';
      if (params.containsKey('port3_width') || params.containsKey('branch_width')) return 'unequalTee';
      if (params.containsKey('port2_width') || params.containsKey('width2')) return 'reducer';
      return 'straight';
    }

    final contract = _detectedContract;
    if (contract != null) {
      if (contract == CmsProductContract.unequalTee || contract.scalingProfile == CmsScalingProfile.unequalTee) return 'unequalTee';
      if (contract == CmsProductContract.equalTee || contract.scalingProfile == CmsScalingProfile.equalTee) return 'equalTee';
      if (contract == CmsProductContract.unequalCross || contract.scalingProfile == CmsScalingProfile.unequalCross) return 'unequalCross';
      if (contract == CmsProductContract.equalCross || contract.scalingProfile == CmsScalingProfile.equalCross) return 'equalCross';
      if (contract == CmsProductContract.straightReducer || contract.scalingProfile == CmsScalingProfile.reducer) return 'reducer';
      if (contract.scalingProfile == CmsScalingProfile.insideRiser) return 'insideRiser';
      if (contract.scalingProfile == CmsScalingProfile.outsideRiser) return 'outsideRiser';
      if (contract.scalingProfile == CmsScalingProfile.flatBend45) return 'flatBend45';
      if (contract.scalingProfile == CmsScalingProfile.flatBend90) return 'flatBend90';
    }

    // Inspect viewModel
    final docType = (widget.viewModel?.document.productType ?? widget.viewModel?.document.itemName ?? '').toLowerCase();
    if (docType.contains('cross')) return docType.contains('unequal') ? 'unequalCross' : 'equalCross';
    if (docType.contains('tee')) return docType.contains('unequal') ? 'unequalTee' : 'equalTee';
    if (docType.contains('reducer')) return 'reducer';
    if (docType.contains('inside_riser')) return 'insideRiser';
    if (docType.contains('outside_riser')) return 'outsideRiser';
    if (docType.contains('bend')) return docType.contains('45') ? 'flatBend45' : 'flatBend90';
    return 'straight';
  }

  Map<String, double> get _currentParams {
    final result = <String, double>{};
    if (widget.instance != null) {
      result['thickness'] = 1.5;
      result['base_flange_size'] = 20.0;
      result['cover_flange_size'] = widget.instance!.coverConfiguration.flangeDepthMm;
      result['coupler_slot_length'] = 20.0;
      result['coupler_slot_width'] = 9.0;
      result['coupler_slot_pitch'] = 25.0;
      result.addAll(widget.instance!.instanceParameters);
      return result;
    }

    final vm = widget.viewModel;
    if (vm != null) {
      // 1. Live scaling controller parameters (if teach scaling or morphing)
      if (vm.scalingController != null) {
        for (final entry in vm.scalingController!.model.parameters.entries) {
          result[entry.key] = entry.value.currentValue;
        }
      }
      // 2. Physical ports
      final ports = vm.verifiedCmsPorts;
      for (int i = 0; i < ports.length; i++) {
        result['port${i + 1}_width'] ??= ports[i].width;
        result['port${i + 1}_height'] ??= ports[i].height;
      }
      if (ports.isNotEmpty) {
        result['width'] ??= ports.first.width;
        result['height'] ??= ports.first.height;
      }
      // 3. Document parameters
      for (final entry in vm.document.parameters.entries) {
        result[entry.key] = entry.value;
      }
      // 4. Metadata cmsTemplate scalingModel parameters
      final cmsTemplate = vm.document.metadata['cmsTemplate'];
      if (cmsTemplate is Map && cmsTemplate['scalingModel'] is Map) {
        final modelParams = cmsTemplate['scalingModel']['parameters'] as Map?;
        if (modelParams != null) {
          for (final entry in modelParams.entries) {
            if (entry.value is Map && entry.value['currentValue'] is num) {
              result[entry.key] ??= (entry.value['currentValue'] as num).toDouble();
            }
          }
        }
      }
      // 5. Metadata cmsParameters
      final meta = vm.document.metadata['cmsParameters'];
      if (meta is Map) {
        for (final entry in meta.entries) {
          if (entry.value is num) {
            result[entry.key.toString()] = (entry.value as num).toDouble();
          }
        }
      }
      // 6. Base thickness & flange sizes
      result['thickness'] ??= vm.document.material.thicknessMm;
      result['base_flange_size'] ??= 20.0;
      result['cover_flange_size'] ??= (vm.document.cover?.properties['flangeDepthMm'] as num?)?.toDouble() ?? 15.0;
    }
    return result;
  }

  void _syncControllers() {
    final p = _currentParams;
    _setControllerText('port1_width', p['port1_width'] ?? p['width'] ?? 100.0);
    _setControllerText('port1_height', p['port1_height'] ?? p['height'] ?? 100.0);
    _setControllerText('port2_width', p['port2_width'] ?? p['width'] ?? 50.0);
    _setControllerText('port2_height', p['port2_height'] ?? p['height'] ?? 50.0);
    _setControllerText('port3_width', p['port3_width'] ?? p['branch_width'] ?? p['width'] ?? 100.0);
    _setControllerText('port3_height', p['port3_height'] ?? p['branch_height'] ?? p['height'] ?? 100.0);
    _setControllerText('port4_width', p['port4_width'] ?? 50.0);
    _setControllerText('port4_height', p['port4_height'] ?? 50.0);
    _setControllerText('width', p['width'] ?? p['port1_width'] ?? 100.0);
    _setControllerText('height', p['height'] ?? p['port1_height'] ?? 100.0);

    // Coupler slot controllers
    _setControllerText('coupler_slot_length', p['coupler_slot_length'] ?? 20.0);
    _setControllerText('coupler_slot_width', p['coupler_slot_width'] ?? 9.0);
    _setControllerText('coupler_slot_pitch', p['coupler_slot_pitch'] ?? 25.0);

    // Flange controllers
    _setControllerText('base_flange_size', p['base_flange_size'] ?? 20.0);
    _setControllerText('cover_flange_size', widget.instance?.coverConfiguration.flangeDepthMm ?? p['cover_flange_size'] ?? 15.0);
    _setControllerText('thickness', p['thickness'] ?? 1.5);
  }

  void _setControllerText(String key, double val) {
    final text = val % 1 == 0 ? val.toInt().toString() : val.toStringAsFixed(1);
    if (_controllers.containsKey(key)) {
      if (_controllers[key]!.text != text) {
        _controllers[key]!.text = text;
      }
    } else {
      _controllers[key] = TextEditingController(text: text);
    }
  }

  void _updateParam(String key, double value) {
    final updated = Map<String, double>.from(_currentParams);
    updated[key] = value;

    if (_arePortsLinked) {
      if (key.endsWith('_width') || key == 'width') {
        updated['port1_width'] = value;
        updated['port2_width'] = value;
        updated['port3_width'] = value;
        updated['port4_width'] = value;
        updated['width'] = value;
        _setControllerText('port1_width', value);
        _setControllerText('port2_width', value);
        _setControllerText('port3_width', value);
        _setControllerText('port4_width', value);
        _setControllerText('width', value);
      } else if (key.endsWith('_height') || key == 'height') {
        updated['port1_height'] = value;
        updated['port2_height'] = value;
        updated['port3_height'] = value;
        updated['port4_height'] = value;
        updated['height'] = value;
        _setControllerText('port1_height', value);
        _setControllerText('port2_height', value);
        _setControllerText('port3_height', value);
        _setControllerText('port4_height', value);
        _setControllerText('height', value);
      }
    }

    if (widget.instance != null && widget.onInstanceChanged != null) {
      var updatedInst = widget.instance!.copyWith(
        instanceParameters: updated,
      );
      if (key == 'cover_flange_size') {
        updatedInst = updatedInst.copyWith(
          coverConfiguration: updatedInst.coverConfiguration.copyWith(
            flangeDepthMm: value,
          ),
        );
      }
      widget.onInstanceChanged!(updatedInst);
    } else if (widget.viewModel != null) {
      widget.viewModel!.applyCmsMorphParameter(key, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLight = widget.isLightTheme;
    final bgCol = isLight ? Colors.white : const Color(0xFF1E293B);
    final borderCol = isLight ? const Color(0xFFE2E8F0) : const Color(0xFF334155);
    final pType = _productType;

    final scrollBody = SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Section 1: All Port's Dimensions ---
          _buildSectionHeader('1. PORT DIMENSIONS', Icons.open_in_full, pType, hasLinkToggle: true),
          const SizedBox(height: 6),
          _buildDynamicPortEditors(pType),
          const SizedBox(height: 12),

          // --- Section 2: Coupler Slots (One Common Size) ---
          _buildSectionHeader('2. COUPLER SLOTS (COMMON SIZE)', Icons.more_horiz, null),
          const SizedBox(height: 6),
          _buildCouplerSlotsSection(),
          const SizedBox(height: 12),

          // --- Section 3: Flange Direction Toggle ---
          _buildSectionHeader('3. BASE FLANGE DIRECTION', Icons.compare_arrows, null),
          const SizedBox(height: 6),
          _buildFlangeDirectionToggle(),
          const SizedBox(height: 12),

          // --- Section 4: Parametric Cover & Flange ---
          _buildSectionHeader('4. PARAMETRIC COVER & FLANGE', Icons.layers_clear, null),
          const SizedBox(height: 6),
          _buildFlangeSizesSection(),
          const SizedBox(height: 12),

          // --- Section 5: Sheet Gauge, Material & Finish ---
          _buildSectionHeader('5. SPECIFICATIONS & GAUGE', Icons.straighten, null),
          const SizedBox(height: 6),
          _buildSpecificationsSection(),
          const SizedBox(height: 12),

          // --- Section 6: Standard Size Quick Presets ---
          _buildPresetsBar(),
          const SizedBox(height: 10),

          // --- Section 7: Live Physical Takeoff HUD ---
          _buildTakeoffHUD(),
          const SizedBox(height: 10),

          // Action Button: Apply / Sync
          SizedBox(
            width: double.infinity,
            height: 28,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
              icon: const Icon(Icons.sync, size: 13),
              label: const Text('Bake & Sync Dimensions', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
              onPressed: () {
                if (widget.instance != null && widget.onInstanceChanged != null) {
                  widget.onInstanceChanged!(widget.instance!.copyWith(instanceParameters: _currentParams));
                } else if (widget.viewModel != null) {
                  widget.viewModel!.commitCmsScaling();
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✓ CMS parameters baked & synchronized across CAD & TDS.'),
                    backgroundColor: Color(0xFF0284C7),
                    duration: Duration(milliseconds: 1500),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );

    return Container(
      width: widget.isDetached ? 330 : double.infinity,
      decoration: BoxDecoration(
        color: bgCol,
        borderRadius: BorderRadius.circular(widget.isDetached ? 10 : 0),
        border: widget.isDetached ? Border.all(color: borderCol, width: 1.0) : null,
        boxShadow: widget.isDetached
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isLight ? 0.12 : 0.4),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisSize: widget.isDetached ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ===================================================================
          // Panel Title Bar (Draggable if detached)
          // ===================================================================
          GestureDetector(
            onPanStart: widget.onDragStart,
            onPanUpdate: widget.onDragUpdate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: widget.isDetached
                    ? const BorderRadius.vertical(top: Radius.circular(9))
                    : BorderRadius.zero,
              ),
              child: Row(
                children: [
                  const Icon(Icons.tune, size: 14, color: Color(0xFF38BDF8)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'CMS PARAMETER INSPECTOR',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.6,
                          ),
                        ),
                        Text(
                          '${_formatProductTitle(pType)} • Live Morph Engine',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 8.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (widget.onDetach != null)
                    IconButton(
                      icon: Icon(
                        widget.isDetached ? Icons.vertical_align_bottom : Icons.open_in_new,
                        size: 14,
                        color: Colors.white70,
                      ),
                      tooltip: widget.isDetached ? 'Dock to Inspector Tab' : 'Detach to Floating Window',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: widget.onDetach,
                    ),
                  if (widget.onClose != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.close, size: 14, color: Colors.white70),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: widget.onClose,
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ===================================================================
          // Scrollable Parameter Body
          // ===================================================================
          if (widget.isDetached)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: (MediaQuery.of(context).size.height - 120).clamp(300.0, 720.0),
              ),
              child: scrollBody,
            )
          else
            Expanded(
              child: scrollBody,
            ),
        ],
      ),
    );
  }

  // ===========================================================================
  // Section Builders
  // ===========================================================================

  Widget _buildSectionHeader(String title, IconData icon, String? productType, {bool hasLinkToggle = false}) {
    final isLight = widget.isLightTheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: const Color(0xFF0284C7)),
            const SizedBox(width: 5),
            Text(
              title,
              style: TextStyle(
                fontSize: 9.2,
                fontWeight: FontWeight.bold,
                color: isLight ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        if (hasLinkToggle)
          InkWell(
            onTap: () => setState(() => _arePortsLinked = !_arePortsLinked),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: _arePortsLinked ? const Color(0xFF0284C7) : (isLight ? const Color(0xFFE2E8F0) : const Color(0xFF334155)),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Row(
                children: [
                  Icon(
                    _arePortsLinked ? Icons.link : Icons.link_off,
                    size: 10,
                    color: _arePortsLinked ? Colors.white : (isLight ? const Color(0xFF64748B) : Colors.white70),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    _arePortsLinked ? 'LINKED' : 'UNLINK',
                    style: TextStyle(
                      fontSize: 7.5,
                      fontWeight: FontWeight.bold,
                      color: _arePortsLinked ? Colors.white : (isLight ? const Color(0xFF64748B) : Colors.white70),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDynamicPortEditors(String pType) {
    if (pType == 'unequalCross') {
      // 4 Ports for Unequal Cross
      return Column(
        children: [
          _buildPortRow('P1', 'North / Main Inlet', 'port1_width', 'port1_height', const Color(0xFF0284C7)),
          const SizedBox(height: 4),
          _buildPortRow('P2', 'South / Main Outlet', 'port2_width', 'port2_height', const Color(0xFF059669)),
          const SizedBox(height: 4),
          _buildPortRow('P3', 'East / Branch 1', 'port3_width', 'port3_height', const Color(0xFFD97706)),
          const SizedBox(height: 4),
          _buildPortRow('P4', 'West / Branch 2', 'port4_width', 'port4_height', const Color(0xFF7C3AED)),
        ],
      );
    } else if (pType == 'equalCross') {
      // Equal Cross: 1 common port setting
      return _buildPortRow('P1-4', '4 Equal Cross Ports', 'width', 'height', const Color(0xFF0284C7));
    } else if (pType == 'unequalTee') {
      // Unequal Tee: 3 distinct ports (P1 Branch, P2 Right, P3 Main)
      return Column(
        children: [
          _buildPortRow('P1', 'Port 1 (Branch)', 'port1_width', 'port1_height', const Color(0xFF7C3AED)),
          const SizedBox(height: 4),
          _buildPortRow('P2', 'Port 2 (Right)', 'port2_width', 'port2_height', const Color(0xFF059669)),
          const SizedBox(height: 4),
          _buildPortRow('P3', 'Port 3 (Main)', 'port3_width', 'port3_height', const Color(0xFF0284C7)),
        ],
      );
    } else if (pType == 'equalTee') {
      // Equal Tee: 3 Equal Ports (W × H)
      return _buildPortRow('TEE', '3 Equal Ports (W × H)', 'width', 'height', const Color(0xFF0284C7));
    } else if (pType == 'reducer') {
      // Reducer: Port 1 (Inlet) + Port 2 (Outlet)
      return Column(
        children: [
          _buildPortRow('INLET', 'Port 1 (Large Inlet)', 'port1_width', 'port1_height', const Color(0xFF0284C7)),
          const SizedBox(height: 4),
          _buildPortRow('OUTLET', 'Port 2 (Small Outlet)', 'port2_width', 'port2_height', const Color(0xFF059669)),
        ],
      );
    } else {
      // Bends, Risers, Straight
      return _buildPortRow('MOUTH', 'Trunking Mouth (W × H)', 'width', 'height', const Color(0xFF0284C7));
    }
  }

  Widget _buildPortRow(String badge, String title, String widthKey, String heightKey, Color color) {
    final isLight = widget.isLightTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: isLight ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: isLight ? const Color(0xFFE2E8F0) : const Color(0xFF334155), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
                child: Text(
                  badge,
                  style: const TextStyle(color: Colors.white, fontSize: 7.5, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w600,
                    color: isLight ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              // Width field with standard width presets: 50, 75, 100, 150, 200, 225, 300, 450, 600
              Expanded(
                child: _buildStepperField(
                  'W (mm)',
                  widthKey,
                  25.0,
                  1200.0,
                  presetSizes: const [50, 75, 100, 150, 200, 225, 300, 450, 600],
                ),
              ),
              const SizedBox(width: 6),
              // Height field with standard height presets: 25, 38, 50, 75, 100, 150
              Expanded(
                child: _buildStepperField(
                  'H (mm)',
                  heightKey,
                  25.0,
                  600.0,
                  presetSizes: const [25, 38, 50, 75, 100, 150],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepperField(String label, String key, double min, double max, {List<double>? presetSizes}) {
    final isLight = widget.isLightTheme;
    final ctrl = _controllers[key] ?? TextEditingController(text: '100');

    return Row(
      children: [
        Text(label, style: TextStyle(fontSize: 8.0, fontWeight: FontWeight.bold, color: isLight ? const Color(0xFF64748B) : const Color(0xFF94A3B8))),
        const SizedBox(width: 4),
        Expanded(
          child: Container(
            height: 24,
            decoration: BoxDecoration(
              color: isLight ? Colors.white : const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: isLight ? const Color(0xFFCBD5E1) : const Color(0xFF475569), width: 0.8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: ctrl,
                    keyboardType: TextInputType.number,
                    style: TextStyle(fontSize: 9.0, fontWeight: FontWeight.bold, color: isLight ? const Color(0xFF0F172A) : Colors.white),
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                      border: InputBorder.none,
                    ),
                    onSubmitted: (val) {
                      final parsed = double.tryParse(val);
                      if (parsed != null && parsed >= min && parsed <= max) {
                        _updateParam(key, parsed);
                      }
                    },
                  ),
                ),
                // Stepper -
                InkWell(
                  onTap: () {
                    final current = double.tryParse(ctrl.text) ?? 100.0;
                    final next = (current - 10.0).clamp(min, max);
                    ctrl.text = next.toStringAsFixed(0);
                    _updateParam(key, next);
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 2),
                    child: Icon(Icons.remove, size: 10, color: Color(0xFF64748B)),
                  ),
                ),
                // Stepper +
                InkWell(
                  onTap: () {
                    final current = double.tryParse(ctrl.text) ?? 100.0;
                    final next = (current + 10.0).clamp(min, max);
                    ctrl.text = next.toStringAsFixed(0);
                    _updateParam(key, next);
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 2),
                    child: Icon(Icons.add, size: 10, color: Color(0xFF64748B)),
                  ),
                ),
                // Compact Dropdown for standard common sizes
                if (presetSizes != null && presetSizes.isNotEmpty)
                  PopupMenuButton<double>(
                    tooltip: 'Common standard sizes',
                    padding: EdgeInsets.zero,
                    iconSize: 13,
                    icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF0284C7)),
                    onSelected: (selectedVal) {
                      ctrl.text = selectedVal.toStringAsFixed(0);
                      _updateParam(key, selectedVal);
                    },
                    itemBuilder: (ctx) {
                      return presetSizes.map((sz) {
                        return PopupMenuItem<double>(
                          value: sz,
                          height: 28,
                          child: Text(
                            '${sz.toStringAsFixed(0)} mm',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        );
                      }).toList();
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --- Section 2: Coupler Slots ---
  Widget _buildCouplerSlotsSection() {
    final isLight = widget.isLightTheme;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: isLight ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: isLight ? const Color(0xFFE2E8F0) : const Color(0xFF334155), width: 0.8),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildStepperField('Slot L', 'coupler_slot_length', 10.0, 40.0)),
              const SizedBox(width: 8),
              Expanded(child: _buildStepperField('Slot W', 'coupler_slot_width', 5.0, 16.0)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(child: _buildStepperField('Pitch', 'coupler_slot_pitch', 15.0, 50.0)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const Text(
                  '4 SLOTS / PORT (M6)',
                  style: TextStyle(fontSize: 7.5, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Section 3: Flange Direction Toggle ---
  Widget _buildFlangeDirectionToggle() {
    final isInside = (_currentParams['flange_direction'] ?? 0.0) == 1.0;
    return Row(
      children: [
        Expanded(
          child: _buildDirectionOption(
            title: 'Outside Return Flange',
            subtitle: 'Standard Return Lip (90°)',
            icon: Icons.keyboard_double_arrow_right,
            isSelected: !isInside,
            onTap: () => _updateParam('flange_direction', 0.0),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _buildDirectionOption(
            title: 'Inside Flange',
            subtitle: 'Flush Exterior Lip (90°)',
            icon: Icons.keyboard_double_arrow_left,
            isSelected: isInside,
            onTap: () => _updateParam('flange_direction', 1.0),
          ),
        ),
      ],
    );
  }

  Widget _buildDirectionOption({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final isLight = widget.isLightTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0284C7) : (isLight ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B)),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: isSelected ? const Color(0xFF38BDF8) : (isLight ? const Color(0xFFCBD5E1) : const Color(0xFF334155)),
            width: 0.8,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 11, color: isSelected ? Colors.white : const Color(0xFF0284C7)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 8.2,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : (isLight ? const Color(0xFF0F172A) : Colors.white),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 6.8,
                color: isSelected ? Colors.white70 : (isLight ? const Color(0xFF64748B) : Colors.white60),
              ),
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }

  // --- Section 4: Parametric Cover & Cover Flange ---
  Widget _buildFlangeSizesSection() {
    final isLight = widget.isLightTheme;
    final coverIncluded = widget.instance != null
        ? widget.instance!.coverConfiguration.included
        : (widget.viewModel?.document.cover != null);

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: isLight ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: isLight ? const Color(0xFFE2E8F0) : const Color(0xFF334155), width: 0.8),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Checkbox(
                    value: coverIncluded,
                    activeColor: const Color(0xFF0284C7),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (val) {
                      final included = val ?? false;
                      if (widget.instance != null && widget.onInstanceChanged != null) {
                        final updated = widget.instance!.copyWith(
                          coverConfiguration: widget.instance!.coverConfiguration.copyWith(
                            included: included,
                          ),
                        );
                        widget.onInstanceChanged!(updated);
                      } else if (widget.viewModel != null) {
                        if (included) {
                          widget.viewModel!.createCoverForCurrentFitting();
                        } else {
                          widget.viewModel!.removeCover();
                        }
                      }
                      setState(() {});
                    },
                  ),
                  Text(
                    'Include Parametric Cover',
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w600,
                      color: isLight ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                    ),
                  ),
                ],
              ),
              if (coverIncluded)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    widget.instance?.coverConfiguration.placementMode3D.toUpperCase() ?? 'EXPLODED',
                    style: const TextStyle(fontSize: 7.0, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                  ),
                ),
            ],
          ),

          // Show Cover Flange editing ONLY when cover is included; otherwise hide it!
          if (coverIncluded) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _buildStepperField(
                    'Cover Flange (mm)',
                    'cover_flange_size',
                    6.0,
                    45.0,
                    presetSizes: const [10, 12, 15, 20, 25],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // --- Section 5: Sheet Gauge, Material & Finish ---
  Widget _buildSpecificationsSection() {
    final isLight = widget.isLightTheme;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: isLight ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: isLight ? const Color(0xFFE2E8F0) : const Color(0xFF334155), width: 0.8),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildStepperField('Thickness', 'thickness', 0.8, 3.5)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Material: ${widget.instance?.material ?? "Pre-Galv DX51D"}',
                  style: TextStyle(
                    fontSize: 7.5,
                    fontWeight: FontWeight.w600,
                    color: isLight ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Quick Dimension Presets ---
  Widget _buildPresetsBar() {
    final isLight = widget.isLightTheme;
    final presets = ['50×50', '100×50', '100×100', '150×100', '200×100', '300×100'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'STANDARD NEMA / BS PRESETS',
          style: TextStyle(fontSize: 7.5, fontWeight: FontWeight.bold, color: isLight ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
        ),
        const SizedBox(height: 3),
        Wrap(
          spacing: 4,
          runSpacing: 3,
          children: presets.map((ps) {
            return InkWell(
              onTap: () {
                final parts = ps.split('×');
                final w = double.tryParse(parts[0]) ?? 100.0;
                final h = double.tryParse(parts[1]) ?? 100.0;
                _updateParam('port1_width', w);
                _updateParam('port1_height', h);
                _setControllerText('port1_width', w);
                _setControllerText('port1_height', h);
              },
              borderRadius: BorderRadius.circular(3),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: isLight ? const Color(0xFFF1F5F9) : const Color(0xFF334155),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: isLight ? const Color(0xFFCBD5E1) : const Color(0xFF475569), width: 0.6),
                ),
                child: Text(
                  ps,
                  style: TextStyle(fontSize: 7.5, fontWeight: FontWeight.bold, color: isLight ? const Color(0xFF334155) : Colors.white),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // --- Physical Takeoff HUD ---
  Widget _buildTakeoffHUD() {
    final isLight = widget.isLightTheme;
    final takeoff = widget.instance?.calculatedTakeoff;

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: isLight ? const Color(0xFF0F172A) : const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildTakeoffItem('BLANK AREA', takeoff != null ? '${takeoff.blankSurfaceAreaM2} m²' : '0.185 m²'),
          _buildTakeoffItem('NET WEIGHT', takeoff != null ? '${takeoff.estimatedNetWeightKg} kg' : '1.45 kg'),
          _buildTakeoffItem('GAUGE', '${_currentParams["thickness"] ?? 1.5} mm'),
        ],
      ),
    );
  }

  Widget _buildTakeoffItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 6.8, color: Color(0xFF94A3B8), fontWeight: FontWeight.bold)),
        Text(value, style: const TextStyle(fontSize: 8.5, color: Color(0xFF00E5FF), fontWeight: FontWeight.bold)),
      ],
    );
  }

  String _formatProductTitle(String pType) {
    switch (pType) {
      case 'unequalCross':
        return 'Unequal Cross Fitting (4 Ports)';
      case 'equalCross':
        return 'Equal Cross Fitting (4 Ports)';
      case 'unequalTee':
        return 'Unequal Tee (3 Ports)';
      case 'equalTee':
        return 'Equal Tee (3 Ports)';
      case 'reducer':
        return 'Straight Reducer (Inlet & Outlet)';
      case 'flatBend45':
        return '45° Flat Bend Fitting';
      case 'flatBend90':
        return '90° Flat Bend Fitting';
      case 'insideRiser':
        return 'Inside Riser Fitting';
      case 'outsideRiser':
        return 'Outside Riser Fitting';
      default:
        return 'Straight Cable Management Fitting';
    }
  }
}
