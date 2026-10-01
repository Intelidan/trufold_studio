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
import '../bend_radius_dialog.dart';
import '../cms_perforation_dialog.dart';

class DdsCmsParameterInspector extends StatefulWidget {
  final DdsProductInstance? instance;
  final ValueChanged<DdsProductInstance>? onInstanceChanged;
  final SheetMetalStudioViewModel? viewModel;
  final VoidCallback? onClose;
  final VoidCallback? onFoldSideways;
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
    this.onFoldSideways,
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
  bool _isFolded = false;
  final Map<String, double> _localParams = {};
  bool? _localCoverIncluded;

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
        _localCoverIncluded = widget.viewModel?.document.cover != null;
      });
    }
  }

  String get _currentCategory {
    if (widget.instance != null) {
      final tId = widget.instance!.templateReference.templateId.toLowerCase();
      final pName = widget.instance!.productName.toLowerCase();
      if (tId.contains('trunk') || pName.contains('trunk')) return 'Trunking Accessories';
      if (tId.contains('tray') || pName.contains('tray')) return 'Tray Accessories';
      if (tId.contains('ladder') || pName.contains('ladder')) return 'Ladder Accessories';
    }
    if (widget.viewModel != null) {
      final doc = widget.viewModel!.document;
      final cat = doc.category;
      if (cat.isNotEmpty && cat != 'None') {
        if (cat.toLowerCase().contains('tray') && !cat.toLowerCase().contains('trunking accessories')) {
          return 'Tray Accessories';
        }
        return cat;
      }
      final meta = doc.metadata;
      final item = doc.itemName.toLowerCase();
      final pType = doc.productType.toLowerCase();
      final source = (meta['sourceFilePath'] as String? ?? '').toLowerCase();
      if (item.contains('tray') || pType.contains('tray') || source.contains('tray')) {
        return 'Tray Accessories';
      }
      if (item.contains('ladder') || pType.contains('ladder') || source.contains('ladder')) {
        return 'Ladder Accessories';
      }
      if (item.contains('trunk') || pType.contains('trunk') || source.contains('trunk')) {
        return 'Trunking Accessories';
      }
    }
    return '';
  }

  bool get _isTrunking {
    final cat = _currentCategory.toLowerCase();
    if (cat == 'trunking accessories' || (cat.contains('trunk') && !cat.contains('tray') && !cat.contains('ladder'))) {
      return true;
    }
    if (widget.viewModel != null) {
      final doc = widget.viewModel!.document;
      final item = doc.itemName.toLowerCase();
      final pType = doc.productType.toLowerCase();
      if ((item.contains('trunk') || pType.contains('trunk')) && !item.contains('tray') && !pType.contains('tray') && !item.contains('ladder') && !pType.contains('ladder')) {
        return true;
      }
    }
    return false;
  }

  bool get _isTrayOrLadder {
    if (_isTrunking) return false;
    final cat = _currentCategory.toLowerCase();
    if (cat.contains('tray') || cat.contains('ladder')) return true;
    if (widget.viewModel != null) {
      final doc = widget.viewModel!.document;
      final item = doc.itemName.toLowerCase();
      final pType = doc.productType.toLowerCase();
      if (item.contains('tray') || item.contains('ladder') || pType.contains('tray') || pType.contains('ladder')) {
        return true;
      }
    }
    return true;
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
      result['include_coupler_flaps'] = 0.0;
      result['coupler_flap_length'] = 30.0;
      result['bend_angle'] = 90.0;
      result['radius'] = 180.0;
      result['has_perforations'] = 1.0;
      result['perforation_pitch'] = 100.0;
      result['perforation_staggered'] = 1.0;
      result['perforation_slot_length'] = 30.0;
      result['perforation_slot_width'] = 7.0;
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
        result['port${i + 1}_width'] ??= ports[i].nominalWidth;
        result['port${i + 1}_height'] ??= ports[i].nominalHeight;
      }
      if (ports.isNotEmpty) {
        result['width'] ??= ports.first.nominalWidth;
        result['height'] ??= ports.first.nominalHeight;
      }
      // 3. Document parameters
      for (final entry in vm.document.parameters.entries) {
        result[entry.key] ??= entry.value;
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
            result[entry.key.toString()] ??= (entry.value as num).toDouble();
          }
        }
      }
      // 6. Base thickness & flange sizes
      result['thickness'] ??= vm.document.material.thicknessMm;
      result['base_flange_size'] ??= 20.0;
      result['flange_direction'] ??= (vm.document.parameters['flange_direction'] ?? 0.0);
      result['cover_flange_size'] ??= ((vm.document.cover?.properties['flangeDepthMm'] as num?)?.toDouble() ?? vm.coverFlangeDepth);

      // Coupler flaps & slots
      result['include_coupler_flaps'] ??= ((vm.scalingController?.includeCouplerFlaps ?? ((vm.document.parameters['include_coupler_flaps'] ?? 0.0) > 0.5)) ? 1.0 : 0.0);
      result['coupler_flap_length'] ??= (vm.scalingController?.couplerFlapLength ?? vm.document.parameters['coupler_flap_length'] ?? 30.0);
      result['coupler_slot_length'] ??= (vm.document.parameters['coupler_slot_length'] ?? 20.0);
      result['coupler_slot_width'] ??= (vm.document.parameters['coupler_slot_width'] ?? 9.0);
      result['coupler_slot_pitch'] ??= (vm.document.parameters['coupler_slot_pitch'] ?? 25.0);

      // 7. Bend angle & radius
      result['bend_angle'] ??= (vm.document.parameters['bend_angle'] ?? vm.document.parameters['angle'] ?? (_productType == 'flatBend45' ? 45.0 : 90.0));
      result['radius'] ??= (vm.document.parameters['radius'] ?? 180.0);

      // 8. Perforation controls
      result['has_perforations'] ??= 1.0;
      result['perforation_pitch'] ??= (vm.scalingController?.perforationPitch ?? 100.0);
      result['perforation_staggered'] ??= 1.0;
      result['perforation_slot_length'] ??= 30.0;
      result['perforation_slot_width'] ??= 7.0;
    }
    // Overlay local reactive state for immediate 0ms UI feedback
    result.addAll(_localParams);
    return result;
  }

  void _syncControllers() {
    final p = _currentParams;
    final ports = widget.viewModel?.verifiedCmsPorts ?? [];
    final p1 = ports.isNotEmpty ? ports[0] : null;
    final p2 = ports.length > 1 ? ports[1] : null;
    final p3 = ports.length > 2 ? ports[2] : null;
    final p4 = ports.length > 3 ? ports[3] : null;

    _setControllerText('port1_width', p['port1_width'] ?? p1?.nominalWidth ?? p['width'] ?? 100.0);
    _setControllerText('port1_height', p['port1_height'] ?? p1?.nominalHeight ?? p['height'] ?? 100.0);
    _setControllerText('port2_width', p['port2_width'] ?? p2?.nominalWidth ?? 50.0);
    _setControllerText('port2_height', p['port2_height'] ?? p2?.nominalHeight ?? 50.0);
    _setControllerText('port3_width', p['port3_width'] ?? p['branch_width'] ?? p3?.nominalWidth ?? 100.0);
    _setControllerText('port3_height', p['port3_height'] ?? p['branch_height'] ?? p3?.nominalHeight ?? 100.0);
    _setControllerText('port4_width', p['port4_width'] ?? p4?.nominalWidth ?? 50.0);
    _setControllerText('port4_height', p['port4_height'] ?? p4?.nominalHeight ?? 50.0);
    _setControllerText('width', p['width'] ?? p['port1_width'] ?? 100.0);
    _setControllerText('height', p['height'] ?? p['port1_height'] ?? 100.0);

    // Coupler slot controllers
    _setControllerText('coupler_slot_length', p['coupler_slot_length'] ?? 20.0);
    _setControllerText('coupler_slot_width', p['coupler_slot_width'] ?? 9.0);
    _setControllerText('coupler_slot_pitch', p['coupler_slot_pitch'] ?? 25.0);
    _setControllerText('coupler_flap_length', p['coupler_flap_length'] ?? 30.0);

    // Bend angle & radius
    _setControllerText('bend_angle', p['bend_angle'] ?? (_productType == 'flatBend45' ? 45.0 : 90.0));
    _setControllerText('radius', p['radius'] ?? 180.0);

    // Perforation controllers
    _setControllerText('perforation_pitch', p['perforation_pitch'] ?? 100.0);
    _setControllerText('perforation_slot_length', p['perforation_slot_length'] ?? 30.0);
    _setControllerText('perforation_slot_width', p['perforation_slot_width'] ?? 7.0);

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
    _localParams[key] = value;
    _setControllerText(key, value);

    final updated = Map<String, double>.from(_currentParams);
    updated[key] = value;

    if (_arePortsLinked) {
      if (key.endsWith('_width') || key == 'width') {
        for (final k in ['port1_width', 'port2_width', 'port3_width', 'port4_width', 'width']) {
          _localParams[k] = value;
          updated[k] = value;
          _setControllerText(k, value);
        }
      } else if (key.endsWith('_height') || key == 'height') {
        for (final k in ['port1_height', 'port2_height', 'port3_height', 'port4_height', 'height']) {
          _localParams[k] = value;
          updated[k] = value;
          _setControllerText(k, value);
        }
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
      if (key == 'bend_angle') {
        updated['angle'] = value;
      }
      widget.onInstanceChanged!(updatedInst);
    } else if (widget.viewModel != null) {
      final vm = widget.viewModel!;
      vm.document.parameters[key] = value;
      if (key == 'flange_direction') {
        vm.document.parameters['flange_direction'] = value;
      } else if (key == 'cover_flange_size') {
        vm.document.parameters['cover_flange_size'] = value;
        vm.setCoverFlangeDepth(value);
      } else if (key == 'include_coupler_flaps') {
        vm.document.parameters['include_coupler_flaps'] = value;
        if (vm.scalingController == null) vm.startTeachScaling();
        vm.scalingController?.setIncludeCouplerFlaps(value > 0.5);
      } else if (key == 'coupler_flap_length') {
        vm.document.parameters['coupler_flap_length'] = value;
        if (vm.scalingController == null) vm.startTeachScaling();
        vm.scalingController?.setCouplerFlapLength(value);
      } else if (key == 'perforation_pitch') {
        vm.scalingController?.setPerforationPitch(value);
      } else if (key == 'radius') {
        vm.document.parameters['radius'] = value;
      }

      if (_arePortsLinked) {
        if (key.endsWith('_width') || key == 'width') {
          vm.applyCmsMorphParameter('width', value);
        } else if (key.endsWith('_height') || key == 'height') {
          vm.applyCmsMorphParameter('height', value);
        }
      }
      vm.applyCmsMorphParameter(key, value);
      if (key == 'bend_angle') {
        vm.applyCmsMorphParameter('angle', value);
      }
    }
    setState(() {});
  }

  /// Resets Width (W) and Height (H) back to baseline template values.
  void _resetDimensions() {
    double baseW = 100.0;
    double baseH = 50.0;

    final vm = widget.viewModel;
    if (vm != null) {
      if (vm.scalingController != null) {
        final ctrl = vm.scalingController!;
        baseW = ctrl.model.parameters['width']?.baselineValue ??
            (ctrl.baselinePorts.isNotEmpty ? ctrl.baselinePorts.first.nominalWidth : 100.0);
        baseH = ctrl.model.parameters['height']?.baselineValue ??
            (ctrl.baselinePorts.isNotEmpty ? ctrl.baselinePorts.first.nominalHeight : 50.0);

        for (int i = 0; i < ctrl.baselinePorts.length; i++) {
          final port = ctrl.baselinePorts[i];
          final pWKey = 'port${i + 1}_width';
          final pHKey = 'port${i + 1}_height';
          final pBaseW = ctrl.model.parameters[pWKey]?.baselineValue ?? port.nominalWidth;
          final pBaseH = ctrl.model.parameters[pHKey]?.baselineValue ?? port.nominalHeight;
          _updateParam(pWKey, pBaseW);
          _updateParam(pHKey, pBaseH);
          _setControllerText(pWKey, pBaseW);
          _setControllerText(pHKey, pBaseH);
        }
      } else if (vm.verifiedCmsPorts.isNotEmpty) {
        baseW = vm.verifiedCmsPorts.first.nominalWidth;
        baseH = vm.verifiedCmsPorts.first.nominalHeight;
        for (int i = 0; i < vm.verifiedCmsPorts.length; i++) {
          final port = vm.verifiedCmsPorts[i];
          final pWKey = 'port${i + 1}_width';
          final pHKey = 'port${i + 1}_height';
          _updateParam(pWKey, port.nominalWidth);
          _updateParam(pHKey, port.nominalHeight);
          _setControllerText(pWKey, port.nominalWidth);
          _setControllerText(pHKey, port.nominalHeight);
        }
      }
    } else if (widget.instance != null) {
      baseW = 100.0;
      baseH = 50.0;
    }

    _updateParam('width', baseW);
    _updateParam('height', baseH);
    _setControllerText('width', baseW);
    _setControllerText('height', baseH);

    setState(() {});
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
          // --- Section 1: All Port's Dimensions & Bend Geometry ---
          _buildSectionHeader('1. PORT DIMENSIONS & BEND GEOMETRY', Icons.open_in_full, pType, hasLinkToggle: true),
          const SizedBox(height: 6),
          _buildDynamicPortEditors(pType),
          const SizedBox(height: 12),

          // --- Section 2: Coupler Slots & Flaps (Common Size) ---
          // Bend Radius and Coupler shouldn't be available for any Trunking Accessories category
          if (!_isTrunking) ...[
            _buildSectionHeader('2. COUPLER SLOTS & FLAPS', Icons.more_horiz, null),
            const SizedBox(height: 6),
            _buildCouplerSlotsSection(),
            const SizedBox(height: 12),
          ],

          // --- Section 3: Floor Bed Perforations & Stamping ---
          _buildSectionHeader('3. FLOOR PERFORATIONS & STAMPING', Icons.grid_view, null),
          const SizedBox(height: 6),
          _buildFloorPerforationsSection(),
          const SizedBox(height: 12),

          // --- Section 4: Flange Direction Toggle ---
          _buildSectionHeader('4. BASE FLANGE DIRECTION', Icons.compare_arrows, null),
          const SizedBox(height: 6),
          _buildFlangeDirectionToggle(),
          const SizedBox(height: 12),

          // --- Section 5: Parametric Cover & Flange ---
          _buildSectionHeader('5. PARAMETRIC COVER & FLANGE', Icons.layers_clear, null),
          const SizedBox(height: 6),
          _buildFlangeSizesSection(),
          const SizedBox(height: 12),

          // --- Section 6: Sheet Gauge, Material & Finish ---
          _buildSectionHeader('6. SPECIFICATIONS & GAUGE', Icons.straighten, null),
          const SizedBox(height: 6),
          _buildSpecificationsSection(),
          const SizedBox(height: 12),

          // --- Section 7: Standard Size Quick Presets ---
          _buildPresetsBar(),
          const SizedBox(height: 10),

          // --- Section 8: Live Physical Takeoff HUD ---
          _buildTakeoffHUD(),
          const SizedBox(height: 10),

          // Action Button: Apply / Sync
          SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
                elevation: 3,
                shadowColor: const Color(0xFF0284C7).withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              icon: const Icon(Icons.sync, size: 16),
              label: const Text(
                'Bake & Sync Dimensions',
                style: TextStyle(fontSize: 13.0, fontWeight: FontWeight.bold, letterSpacing: 0.4),
              ),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final hasFiniteWidth = constraints.maxWidth.isFinite;
        final hasFiniteHeight = constraints.maxHeight.isFinite;
        final panelWidth = widget.isDetached
            ? 400.0
            : (hasFiniteWidth ? double.infinity : 395.0);

        return Container(
          width: panelWidth,
          decoration: BoxDecoration(
            color: bgCol,
            borderRadius: BorderRadius.circular(widget.isDetached ? 10 : 0),
            border: widget.isDetached ? Border.all(color: borderCol, width: 1.0) : null,
            boxShadow: widget.isDetached
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isLight ? 0.15 : 0.45),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ===================================================================
              // Panel Title Bar (Draggable if detached)
              // ===================================================================
              GestureDetector(
                onPanStart: widget.onDragStart,
                onPanUpdate: widget.onDragUpdate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: widget.isDetached
                        ? (_isFolded ? BorderRadius.circular(9) : const BorderRadius.vertical(top: Radius.circular(9)))
                        : BorderRadius.zero,
                    border: Border(
                      bottom: BorderSide(color: isLight ? const Color(0xFFE2E8F0) : const Color(0xFF334155), width: 1.0),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.4), width: 1.0),
                        ),
                        child: const Icon(Icons.tune, size: 17, color: Color(0xFF38BDF8)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'CMS PARAMETER INSPECTOR',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13.0,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              '${_formatProductTitle(pType)} • Live Morph Engine',
                              style: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 11.0,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (widget.isDetached) ...[
                        IconButton(
                          icon: Icon(
                            _isFolded ? Icons.unfold_more : Icons.unfold_less,
                            size: 18,
                            color: Colors.white70,
                          ),
                          tooltip: _isFolded ? 'Expand Inspector' : 'Fold to Header Bar',
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(),
                          onPressed: () => setState(() => _isFolded = !_isFolded),
                        ),
                        const SizedBox(width: 6),
                      ],
                      // Arrow button for sideways folding (when docked on right side)
                      if (!widget.isDetached) ...[
                        Tooltip(
                          message: 'Fold / Collapse Sideways',
                          child: InkWell(
                            onTap: widget.onFoldSideways ?? widget.onClose,
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Icon(
                                Icons.chevron_right,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (widget.onDetach != null)
                        IconButton(
                          icon: Icon(
                            widget.isDetached ? Icons.vertical_align_bottom : Icons.open_in_new,
                            size: 17,
                            color: Colors.white70,
                          ),
                          tooltip: widget.isDetached ? 'Dock to 2D View' : 'Detach to Floating Window',
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(),
                          onPressed: widget.onDetach,
                        ),
                      if (widget.onClose != null) ...[
                        const SizedBox(width: 6),
                        IconButton(
                          icon: const Icon(Icons.close, size: 17, color: Colors.white70),
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(),
                          onPressed: widget.onClose,
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // ===================================================================
              // Scrollable Parameter Body (Hidden when folded)
              // ===================================================================
              if (!_isFolded) ...[
                if (widget.isDetached || !hasFiniteHeight)
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
            ],
          ),
        );
      },
    );
  }

  // ===========================================================================
  // Section Builders
  // ===========================================================================

  Widget _buildSectionHeader(String title, IconData icon, String? productType, {bool hasLinkToggle = false}) {
    final isLight = widget.isLightTheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF0284C7)),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: isLight ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
              letterSpacing: 0.4,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (hasLinkToggle) ...[
          const SizedBox(width: 6),
          // Reset Dimensions (W, H) Button
          InkWell(
            onTap: _resetDimensions,
            borderRadius: BorderRadius.circular(4),
            child: Tooltip(
              message: 'Reset (W, H) to baseline',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isLight ? const Color(0xFFF1F5F9) : const Color(0xFF334155),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: isLight ? const Color(0xFFCBD5E1) : const Color(0xFF475569), width: 0.8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.restart_alt, size: 13, color: Color(0xFF0284C7)),
                    SizedBox(width: 3),
                    Text(
                      'RESET',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0284C7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Link / Unlink Ports Toggle
          InkWell(
            onTap: () => setState(() => _arePortsLinked = !_arePortsLinked),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _arePortsLinked ? const Color(0xFF0284C7) : (isLight ? const Color(0xFFE2E8F0) : const Color(0xFF334155)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _arePortsLinked ? Icons.link : Icons.link_off,
                    size: 13,
                    color: _arePortsLinked ? Colors.white : (isLight ? const Color(0xFF64748B) : Colors.white70),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    _arePortsLinked ? 'LINKED' : 'UNLINK',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: _arePortsLinked ? Colors.white : (isLight ? const Color(0xFF64748B) : Colors.white70),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDynamicPortEditors(String pType) {
    if (pType == 'unequalCross') {
      // 4 Ports for Unequal Cross
      return Column(
        children: [
          _buildPortRow('P1', 'North / Main Inlet', 'port1_width', 'port1_height', const Color(0xFF0284C7)),
          const SizedBox(height: 6),
          _buildPortRow('P2', 'South / Main Outlet', 'port2_width', 'port2_height', const Color(0xFF059669)),
          const SizedBox(height: 6),
          _buildPortRow('P3', 'East / Branch 1', 'port3_width', 'port3_height', const Color(0xFFD97706)),
          const SizedBox(height: 6),
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
          const SizedBox(height: 6),
          _buildPortRow('P2', 'Port 2 (Right)', 'port2_width', 'port2_height', const Color(0xFF059669)),
          const SizedBox(height: 6),
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
          const SizedBox(height: 6),
          _buildPortRow('OUTLET', 'Port 2 (Small Outlet)', 'port2_width', 'port2_height', const Color(0xFF059669)),
        ],
      );
    } else {
      // Bends, Risers, Straight
      final isBend = pType == 'flatBend45' ||
          pType == 'flatBend90' ||
          pType == 'insideRiser' ||
          pType == 'outsideRiser' ||
          pType.contains('bend') ||
          _currentParams.containsKey('bend_angle') ||
          _currentParams.containsKey('radius');
      final isRiser = pType == 'insideRiser' || pType == 'outsideRiser';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPortRow(
            isRiser ? 'RISER MOUTH' : (isBend ? 'BEND MOUTH' : 'MOUTH'),
            _isTrayOrLadder ? 'Cable Tray Mouth (W × H)' : 'Trunking Mouth (W × H)',
            'width',
            'height',
            const Color(0xFF0284C7),
          ),
          if (isBend) ...[
            const SizedBox(height: 8),
            _buildBendAngleAndRadiusSection(isRiser: isRiser),
          ],
        ],
      );
    }
  }

  Widget _buildBendAngleAndRadiusSection({bool isRiser = false}) {
    final isLight = widget.isLightTheme;
    final curRadius = _currentParams['radius'] ?? 180.0;
    final curAngle = _currentParams['bend_angle'] ??
        (_currentParams['angle'] ?? (_productType == 'flatBend45' ? 45.0 : 90.0));
    final showBendRadius = !_isTrunking;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isLight ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isLight ? const Color(0xFFE2E8F0) : const Color(0xFF334155), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Bend Angle Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFF7C3AED), borderRadius: BorderRadius.circular(4)),
                child: const Text(
                  'ANGLE',
                  style: TextStyle(color: Colors.white, fontSize: 10.0, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isRiser ? 'Riser Elevation Angle (θ)' : 'Bend Sweep Angle (θ)',
                  style: TextStyle(
                    fontSize: 12.0,
                    fontWeight: FontWeight.bold,
                    color: isLight ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${curAngle.toStringAsFixed(0)}°',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF7C3AED),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Angle Presets Chips: 30°, 45°, 60°, 90°
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final anglePreset in [30.0, 45.0, 60.0, 90.0]) ...[
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2.5),
                    child: InkWell(
                      onTap: () {
                        _updateParam('bend_angle', anglePreset);
                        _updateParam('angle', anglePreset);
                      },
                      borderRadius: BorderRadius.circular(5),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: (curAngle - anglePreset).abs() < 1e-3
                              ? const Color(0xFF7C3AED).withValues(alpha: 0.2)
                              : (isLight ? Colors.white : const Color(0xFF1E293B)),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: (curAngle - anglePreset).abs() < 1e-3
                                ? const Color(0xFF7C3AED)
                                : (isLight ? const Color(0xFFCBD5E1) : const Color(0xFF475569)),
                            width: (curAngle - anglePreset).abs() < 1e-3 ? 1.4 : 0.8,
                          ),
                        ),
                        child: Text(
                          '${anglePreset.toStringAsFixed(0)}°',
                          style: TextStyle(
                            fontSize: 12.0,
                            fontWeight: (curAngle - anglePreset).abs() < 1e-3 ? FontWeight.bold : FontWeight.w600,
                            color: (curAngle - anglePreset).abs() < 1e-3
                                ? const Color(0xFF7C3AED)
                                : (isLight ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          // 2. Throat Radius Row
          if (showBendRadius) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFF0284C7), borderRadius: BorderRadius.circular(4)),
                  child: const Text(
                    'RADIUS',
                    style: TextStyle(color: Colors.white, fontSize: 10.0, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isRiser ? 'Riser Inside Arc Radius (R)' : 'Inside Throat Bend Radius (R)',
                    style: TextStyle(
                      fontSize: 12.0,
                      fontWeight: FontWeight.bold,
                      color: isLight ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${curRadius.toStringAsFixed(0)} mm',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0284C7),
                  ),
                ),
                const SizedBox(width: 6),
                // Prominent Bend Radius Dialog / Fine-Tune Button
                InkWell(
                  onTap: () {
                    final vm = widget.viewModel;
                    if (vm != null && vm.document.bends.isNotEmpty) {
                      BendRadiusDialog.show(context, vm, vm.document.bends.first);
                    }
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF0284C7), width: 0.8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.rounded_corner, size: 13, color: Color(0xFF0284C7)),
                        SizedBox(width: 3),
                        Text(
                          'BEND RADIUS',
                          style: TextStyle(fontSize: 10.0, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text('100', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: isLight ? const Color(0xFF64748B) : const Color(0xFF94A3B8))),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3.0,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.5),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
                    ),
                    child: Slider(
                      value: curRadius.clamp(100.0, 900.0),
                      min: 100.0,
                      max: 900.0,
                      divisions: 80,
                      activeColor: const Color(0xFF0284C7),
                      inactiveColor: isLight ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
                      onChanged: (val) {
                        _updateParam('radius', val);
                      },
                    ),
                  ),
                ),
                Text('900', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: isLight ? const Color(0xFF64748B) : const Color(0xFF94A3B8))),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: [
                for (final preset in [100.0, 150.0, 180.0, 300.0, 450.0, 600.0, 900.0]) ...[
                  InkWell(
                    onTap: () => _updateParam('radius', preset),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: (curRadius - preset).abs() < 1e-3
                            ? const Color(0xFF0284C7).withValues(alpha: 0.2)
                            : (isLight ? Colors.white : const Color(0xFF1E293B)),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: (curRadius - preset).abs() < 1e-3
                              ? const Color(0xFF0284C7)
                              : (isLight ? const Color(0xFFCBD5E1) : const Color(0xFF475569)),
                          width: (curRadius - preset).abs() < 1e-3 ? 1.2 : 0.6,
                        ),
                      ),
                      child: Text(
                        '${preset.toStringAsFixed(0)} mm',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: (curRadius - preset).abs() < 1e-3 ? FontWeight.bold : FontWeight.w500,
                          color: (curRadius - preset).abs() < 1e-3
                              ? const Color(0xFF0284C7)
                              : (isLight ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPortRow(String badge, String title, String widthKey, String heightKey, Color color) {
    final isLight = widget.isLightTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isLight ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isLight ? const Color(0xFFE2E8F0) : const Color(0xFF334155), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                child: Text(
                  badge,
                  style: const TextStyle(color: Colors.white, fontSize: 10.0, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.0,
                    fontWeight: FontWeight.bold,
                    color: isLight ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              InkWell(
                onTap: _resetDimensions,
                borderRadius: BorderRadius.circular(4),
                child: Tooltip(
                  message: 'Reset (W, H) to baseline',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Icon(Icons.restart_alt, size: 15, color: isLight ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              // Width field with standard width presets
              Expanded(
                child: _buildStepperField(
                  'W (mm)',
                  widthKey,
                  25.0,
                  1200.0,
                  step: 25.0,
                  presetSizes: const [50, 75, 100, 150, 200, 225, 300, 450, 600, 750, 900, 1000, 1200],
                ),
              ),
              const SizedBox(width: 8),
              // Height field with standard height presets
              Expanded(
                child: _buildStepperField(
                  'H (mm)',
                  heightKey,
                  25.0,
                  250.0,
                  step: 25.0,
                  presetSizes: const [25, 38, 50, 75, 100, 150, 200, 250],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepperField(
    String label,
    String key,
    double min,
    double max, {
    double step = 10.0,
    int decimals = 0,
    List<double>? presetSizes,
  }) {
    final isLight = widget.isLightTheme;
    final ctrl = _controllers[key] ?? TextEditingController(text: '100');

    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12.0,
            fontWeight: FontWeight.bold,
            color: isLight ? const Color(0xFF475569) : const Color(0xFF94A3B8),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Container(
            height: 34,
            decoration: BoxDecoration(
              color: isLight ? Colors.white : const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: isLight ? const Color(0xFFCBD5E1) : const Color(0xFF475569), width: 0.9),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: ctrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: isLight ? const Color(0xFF0F172A) : Colors.white,
                    ),
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                      border: InputBorder.none,
                    ),
                    onChanged: (val) {
                      final parsed = double.tryParse(val);
                      if (parsed != null && parsed >= min && parsed <= max) {
                        _updateParam(key, parsed);
                      }
                    },
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
                    final next = (current - step).clamp(min, max);
                    ctrl.text = decimals == 0 ? next.toStringAsFixed(0) : next.toStringAsFixed(decimals);
                    _updateParam(key, next);
                  },
                  child: Container(
                    width: 26,
                    height: 34,
                    alignment: Alignment.center,
                    child: Icon(Icons.remove, size: 16, color: isLight ? const Color(0xFF475569) : const Color(0xFF94A3B8)),
                  ),
                ),
                // Stepper +
                InkWell(
                  onTap: () {
                    final current = double.tryParse(ctrl.text) ?? 100.0;
                    final next = (current + step).clamp(min, max);
                    ctrl.text = decimals == 0 ? next.toStringAsFixed(0) : next.toStringAsFixed(decimals);
                    _updateParam(key, next);
                  },
                  child: Container(
                    width: 26,
                    height: 34,
                    alignment: Alignment.center,
                    child: Icon(Icons.add, size: 16, color: isLight ? const Color(0xFF475569) : const Color(0xFF94A3B8)),
                  ),
                ),
                // Compact Dropdown for standard common sizes
                if (presetSizes != null && presetSizes.isNotEmpty)
                  PopupMenuButton<double>(
                    tooltip: 'Common standard sizes',
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF0284C7)),
                    onSelected: (selectedVal) {
                      ctrl.text = decimals == 0 ? selectedVal.toStringAsFixed(0) : selectedVal.toStringAsFixed(decimals);
                      _updateParam(key, selectedVal);
                    },
                    itemBuilder: (ctx) {
                      return presetSizes.map((sz) {
                        return PopupMenuItem<double>(
                          value: sz,
                          height: 32,
                          child: Text(
                            decimals == 0 ? '${sz.toStringAsFixed(0)} mm' : '${sz.toStringAsFixed(decimals)} mm',
                            style: const TextStyle(fontSize: 12.0, fontWeight: FontWeight.w600),
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

  // --- Section 2: Coupler Slots & Flaps ---
  Widget _buildCouplerSlotsSection() {
    final isLight = widget.isLightTheme;
    final hasFlaps = (_currentParams['include_coupler_flaps'] ?? 0.0) > 0.5;
    final flapLen = _currentParams['coupler_flap_length'] ?? 30.0;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isLight ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isLight ? const Color(0xFFE2E8F0) : const Color(0xFF334155), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildStepperField(
                  'Slot L',
                  'coupler_slot_length',
                  10.0,
                  40.0,
                  step: 5.0,
                  presetSizes: const [15, 20, 25, 30],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStepperField(
                  'Slot W',
                  'coupler_slot_width',
                  5.0,
                  16.0,
                  step: 1.0,
                  presetSizes: const [7, 9, 11, 13],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _buildStepperField(
                  'Pitch',
                  'coupler_slot_pitch',
                  15.0,
                  50.0,
                  step: 5.0,
                  presetSizes: const [20, 25, 30, 35, 40],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.4), width: 0.8),
                ),
                child: const Text(
                  '4 SLOTS / PORT (M6)',
                  style: TextStyle(fontSize: 10.0, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Prominent Coupler Flap Addition Action Button for Tray & Ladder
          InkWell(
            onTap: () {
              final nextVal = hasFlaps ? 0.0 : 1.0;
              _updateParam('include_coupler_flaps', nextVal);
            },
            borderRadius: BorderRadius.circular(6),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: hasFlaps
                    ? const Color(0xFF4F46E5).withValues(alpha: 0.18)
                    : (isLight ? Colors.white : const Color(0xFF1E293B)),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: hasFlaps ? const Color(0xFF6366F1) : (isLight ? const Color(0xFFCBD5E1) : const Color(0xFF475569)),
                  width: hasFlaps ? 1.5 : 1.0,
                ),
                boxShadow: hasFlaps
                    ? [
                        BoxShadow(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.25),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  Icon(
                    hasFlaps ? Icons.check_circle : Icons.add_circle_outline,
                    size: 20,
                    color: hasFlaps ? const Color(0xFF818CF8) : const Color(0xFF6366F1),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasFlaps ? 'Coupler Flaps Active' : 'Add Coupler Flaps',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: hasFlaps
                                ? (isLight ? const Color(0xFF4338CA) : const Color(0xFFE0E7FF))
                                : (isLight ? const Color(0xFF1E293B) : Colors.white),
                          ),
                        ),
                        Text(
                          hasFlaps
                              ? 'Integrated cheek tabs with 4× M6 slots • ${flapLen.toStringAsFixed(0)} mm'
                              : 'Add integrated folding connection flaps to port cheek walls',
                          style: TextStyle(
                            fontSize: 10.0,
                            color: isLight ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: hasFlaps ? const Color(0xFF6366F1) : const Color(0xFF6366F1).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      hasFlaps ? 'ACTIVE' : '+ ADD',
                      style: TextStyle(
                        fontSize: 10.0,
                        fontWeight: FontWeight.bold,
                        color: hasFlaps ? Colors.white : const Color(0xFF6366F1),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (hasFlaps) ...[
            const SizedBox(height: 8),
            _buildStepperField(
              'Flap Length (mm)',
              'coupler_flap_length',
              20.0,
              60.0,
              step: 5.0,
              presetSizes: const [25, 30, 35, 40, 50],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [25.0, 30.0, 35.0, 40.0, 50.0].map((preset) {
                final isCur = (flapLen - preset).abs() < 1e-3;
                return InkWell(
                  onTap: () => _updateParam('coupler_flap_length', preset),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: isCur
                          ? const Color(0xFF6366F1).withValues(alpha: 0.2)
                          : (isLight ? Colors.white : const Color(0xFF1E293B)),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isCur
                            ? const Color(0xFF6366F1)
                            : (isLight ? const Color(0xFFCBD5E1) : const Color(0xFF475569)),
                        width: isCur ? 1.0 : 0.6,
                      ),
                    ),
                    child: Text(
                      '${preset.toStringAsFixed(0)} mm',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: isCur ? FontWeight.bold : FontWeight.w500,
                        color: isCur
                            ? const Color(0xFF6366F1)
                            : (isLight ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  // --- Section 3: Floor Bed Perforations & Stamping ---
  Widget _buildFloorPerforationsSection() {
    final isLight = widget.isLightTheme;
    final hasPerf = (_currentParams['has_perforations'] ?? 1.0) > 0.5;
    final curPitch = _currentParams['perforation_pitch'] ?? 100.0;
    final isStaggered = (_currentParams['perforation_staggered'] ?? 1.0) > 0.5;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isLight ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isLight ? const Color(0xFFE2E8F0) : const Color(0xFF334155), width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Enable Toggle Switch
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: hasPerf ? const Color(0xFF059669) : const Color(0xFF64748B),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  hasPerf ? 'ACTIVE' : 'SOLID',
                  style: const TextStyle(color: Colors.white, fontSize: 10.0, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Floor Bed Perforations',
                  style: TextStyle(
                    fontSize: 12.0,
                    fontWeight: FontWeight.bold,
                    color: isLight ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                  ),
                ),
              ),
              Switch(
                value: hasPerf,
                activeThumbColor: const Color(0xFF059669),
                activeTrackColor: const Color(0xFF059669).withValues(alpha: 0.35),
                onChanged: (val) {
                  _updateParam('has_perforations', val ? 1.0 : 0.0);
                },
              ),
            ],
          ),
          if (hasPerf) ...[
            const SizedBox(height: 8),
            // Row 2: Perforation Pitch Presets (50, 75, 80, 100, 150 mm)
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Pitch (Center-to-Center)',
                    style: TextStyle(
                      fontSize: 11.0,
                      fontWeight: FontWeight.w600,
                      color: isLight ? const Color(0xFF475569) : const Color(0xFF94A3B8),
                    ),
                  ),
                ),
                Text(
                  '${curPitch.toStringAsFixed(0)} mm',
                  style: const TextStyle(fontSize: 12.0, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final pitchPreset in [50.0, 75.0, 80.0, 100.0, 150.0]) ...[
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: InkWell(
                        onTap: () => _updateParam('perforation_pitch', pitchPreset),
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 5.5),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: (curPitch - pitchPreset).abs() < 1e-3
                                ? const Color(0xFF059669).withValues(alpha: 0.2)
                                : (isLight ? Colors.white : const Color(0xFF1E293B)),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: (curPitch - pitchPreset).abs() < 1e-3
                                  ? const Color(0xFF059669)
                                  : (isLight ? const Color(0xFFCBD5E1) : const Color(0xFF475569)),
                              width: (curPitch - pitchPreset).abs() < 1e-3 ? 1.2 : 0.7,
                            ),
                          ),
                          child: Text(
                            pitchPreset.toStringAsFixed(0),
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: (curPitch - pitchPreset).abs() < 1e-3 ? FontWeight.bold : FontWeight.w600,
                              color: (curPitch - pitchPreset).abs() < 1e-3
                                  ? const Color(0xFF059669)
                                  : (isLight ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            // Row 3: Slot Length and Slot Width steppers
            Row(
              children: [
                Expanded(
                  child: _buildStepperField(
                    'Slot L',
                    'perforation_slot_length',
                    15.0,
                    50.0,
                    step: 5.0,
                    decimals: 0,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStepperField(
                    'Slot W',
                    'perforation_slot_width',
                    5.0,
                    15.0,
                    step: 1.0,
                    decimals: 0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Row 4: Grid Layout (Staggered vs Inline)
            Row(
              children: [
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _updateParam('perforation_staggered', 1.0),
                      borderRadius: BorderRadius.circular(5),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isStaggered
                              ? const Color(0xFF0284C7).withValues(alpha: 0.18)
                              : (isLight ? Colors.white : const Color(0xFF1E293B)),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: isStaggered
                                ? const Color(0xFF0284C7)
                                : (isLight ? const Color(0xFFCBD5E1) : const Color(0xFF475569)),
                            width: isStaggered ? 1.2 : 0.7,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.grain, size: 14, color: isStaggered ? const Color(0xFF0284C7) : Colors.grey),
                            const SizedBox(width: 5),
                            Text(
                              'Staggered (Zig-Zag)',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: isStaggered ? FontWeight.bold : FontWeight.w500,
                                color: isStaggered ? const Color(0xFF0284C7) : (isLight ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _updateParam('perforation_staggered', 0.0),
                      borderRadius: BorderRadius.circular(5),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: !isStaggered
                              ? const Color(0xFF0284C7).withValues(alpha: 0.18)
                              : (isLight ? Colors.white : const Color(0xFF1E293B)),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: !isStaggered
                                ? const Color(0xFF0284C7)
                                : (isLight ? const Color(0xFFCBD5E1) : const Color(0xFF475569)),
                            width: !isStaggered ? 1.2 : 0.7,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.view_comfy, size: 14, color: !isStaggered ? const Color(0xFF0284C7) : Colors.grey),
                            const SizedBox(width: 5),
                            Text(
                              'Inline (Uniform Grid)',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: !isStaggered ? FontWeight.bold : FontWeight.w500,
                                color: !isStaggered ? const Color(0xFF0284C7) : (isLight ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (widget.viewModel != null) ...[
              const SizedBox(height: 8),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => CmsPerforationDialog.show(context, widget.viewModel!),
                  borderRadius: BorderRadius.circular(5),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    decoration: BoxDecoration(
                      color: isLight ? const Color(0xFFF1F5F9) : const Color(0xFF334155).withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: isLight ? const Color(0xFFCBD5E1) : const Color(0xFF475569), width: 0.8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.tune, size: 15, color: isLight ? const Color(0xFF475569) : const Color(0xFF94A3B8)),
                        const SizedBox(width: 5),
                        Text(
                          'Open Pattern Stamping Tool...',
                          style: TextStyle(
                            fontSize: 11.0,
                            fontWeight: FontWeight.bold,
                            color: isLight ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ] else ...[
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Perforation stamping disabled. Blank plate floor will be cut as a solid flat face.',
                style: TextStyle(
                  fontSize: 10.5,
                  fontStyle: FontStyle.italic,
                  color: isLight ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --- Section 4: Flange Direction Toggle ---
  Widget _buildFlangeDirectionToggle() {
    final isInside = (_currentParams['flange_direction'] ?? 0.0) == 0.0;
    return Row(
      children: [
        Expanded(
          child: _buildDirectionOption(
            title: 'Inside Flange',
            subtitle: 'Standard Return Lip (90°)',
            icon: Icons.keyboard_double_arrow_left,
            isSelected: isInside,
            onTap: () {
              setState(() {
                _localParams['flange_direction'] = 0.0;
              });
              _updateParam('flange_direction', 0.0);
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildDirectionOption(
            title: 'Outside Return Flange',
            subtitle: 'Flush Exterior Lip (90°)',
            icon: Icons.keyboard_double_arrow_right,
            isSelected: !isInside,
            onTap: () {
              setState(() {
                _localParams['flange_direction'] = 1.0;
              });
              _updateParam('flange_direction', 1.0);
            },
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            gradient: isSelected
                ? const LinearGradient(
                    colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: isSelected
                ? null
                : (isLight ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B)),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF38BDF8)
                  : (isLight ? const Color(0xFFCBD5E1) : const Color(0xFF334155)),
              width: isSelected ? 1.5 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.35),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: isSelected ? Colors.white : const Color(0xFF0284C7),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 12.0,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? Colors.white
                            : (isLight ? const Color(0xFF0F172A) : Colors.white),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isSelected)
                    const Icon(Icons.check_circle, size: 14, color: Colors.white),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w500,
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.85)
                      : (isLight ? const Color(0xFF64748B) : Colors.white60),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Section 5: Parametric Cover & Cover Flange ---
  Widget _buildFlangeSizesSection() {
    final isLight = widget.isLightTheme;
    final coverIncluded = _localCoverIncluded ?? (widget.instance != null
        ? widget.instance!.coverConfiguration.included
        : (widget.viewModel?.document.cover != null));

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isLight ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: coverIncluded
              ? const Color(0xFF0284C7).withValues(alpha: 0.5)
              : (isLight ? const Color(0xFFE2E8F0) : const Color(0xFF334155)),
          width: 1.0,
        ),
      ),
      child: Column(
        children: [
          // Clickable Row / Card for Include Parametric Cover
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(5),
              onTap: () {
                final newIncluded = !coverIncluded;
                setState(() {
                  _localCoverIncluded = newIncluded;
                });
                if (widget.instance != null && widget.onInstanceChanged != null) {
                  final updated = widget.instance!.copyWith(
                    coverConfiguration: widget.instance!.coverConfiguration.copyWith(
                      included: newIncluded,
                    ),
                  );
                  widget.onInstanceChanged!(updated);
                } else if (widget.viewModel != null) {
                  if (newIncluded) {
                    widget.viewModel!.createCoverForCurrentFitting();
                  } else {
                    widget.viewModel!.removeCover();
                  }
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                child: Row(
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
                            setState(() {
                              _localCoverIncluded = included;
                            });
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
                          },
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Include Parametric Cover',
                          style: TextStyle(
                            fontSize: 12.0,
                            fontWeight: FontWeight.bold,
                            color: isLight ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                          ),
                        ),
                      ],
                    ),
                    if (coverIncluded)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.5), width: 0.8),
                        ),
                        child: Text(
                          widget.instance?.coverConfiguration.placementMode3D.toUpperCase() ?? 'EXPLODED',
                          style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Show Cover Flange editing ONLY when cover is included; otherwise hide it!
          if (coverIncluded) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildStepperField(
                    'Cover Flange',
                    'cover_flange_size',
                    6.0,
                    45.0,
                    step: 1.0,
                    decimals: 0,
                    presetSizes: const [10, 12, 15, 20, 25],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            // Quick preset chips for cover flange
            Row(
              children: [
                Text(
                  'Presets:',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: isLight ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(width: 6),
                for (final sz in [10.0, 12.0, 15.0, 20.0, 25.0]) ...[
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: InkWell(
                      onTap: () => _updateParam('cover_flange_size', sz),
                      borderRadius: BorderRadius.circular(3),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: ((_currentParams['cover_flange_size'] ?? 15.0) - sz).abs() < 1e-2
                              ? const Color(0xFF0284C7).withValues(alpha: 0.2)
                              : (isLight ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B)),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: ((_currentParams['cover_flange_size'] ?? 15.0) - sz).abs() < 1e-2
                                ? const Color(0xFF0284C7)
                                : (isLight ? const Color(0xFFCBD5E1) : const Color(0xFF475569)),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          '${sz.toInt()}mm',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: ((_currentParams['cover_flange_size'] ?? 15.0) - sz).abs() < 1e-2
                                ? const Color(0xFF0284C7)
                                : (isLight ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  // --- Section 6: Sheet Gauge, Material & Finish ---
  Widget _buildSpecificationsSection() {
    final isLight = widget.isLightTheme;
    final curThick = _currentParams['thickness'] ?? 1.5;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isLight ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isLight ? const Color(0xFFE2E8F0) : const Color(0xFF334155), width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                flex: 6,
                child: _buildStepperField(
                  'Thickness',
                  'thickness',
                  0.6,
                  5.0,
                  step: 0.1,
                  decimals: 1,
                  presetSizes: const [0.8, 1.0, 1.2, 1.5, 2.0, 2.5, 3.0],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 5,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
                  decoration: BoxDecoration(
                    color: isLight ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: isLight ? const Color(0xFFCBD5E1) : const Color(0xFF475569), width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.shield_outlined, size: 15, color: Color(0xFF0284C7)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          widget.instance?.material ?? 'Pre-Galv DX51D',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: isLight ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          // Quick gauge chips
          Row(
            children: [
              Text(
                'Gauge:',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: isLight ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                ),
              ),
              const SizedBox(width: 6),
              for (final th in [0.8, 1.0, 1.2, 1.5, 2.0, 2.5, 3.0]) ...[
                Padding(
                  padding: const EdgeInsets.only(right: 3),
                  child: InkWell(
                    onTap: () {
                      _updateParam('thickness', th);
                    },
                    borderRadius: BorderRadius.circular(3),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: (curThick - th).abs() < 0.05
                            ? const Color(0xFF0284C7).withValues(alpha: 0.2)
                            : (isLight ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B)),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: (curThick - th).abs() < 0.05
                              ? const Color(0xFF0284C7)
                              : (isLight ? const Color(0xFFCBD5E1) : const Color(0xFF475569)),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        '${th.toStringAsFixed(1)}mm',
                        style: TextStyle(
                          fontSize: 10.0,
                          fontWeight: (curThick - th).abs() < 0.05 ? FontWeight.bold : FontWeight.w500,
                          color: (curThick - th).abs() < 0.05
                              ? const Color(0xFF0284C7)
                              : (isLight ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // --- Section 7: Quick Dimension Presets ---
  Widget _buildPresetsBar() {
    final isLight = widget.isLightTheme;
    final presets = ['50×50', '100×50', '100×100', '150×100', '200×100', '300×100'];
    final curW = _currentParams['width'] ?? 100.0;
    final curH = _currentParams['height'] ?? 50.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.dashboard_customize, size: 14, color: isLight ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
            const SizedBox(width: 4),
            Text(
              'STANDARD NEMA / BS PRESETS',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.4,
                color: isLight ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: presets.map((ps) {
            final parts = ps.split('×');
            final pw = double.tryParse(parts[0]) ?? 100.0;
            final ph = double.tryParse(parts[1]) ?? 100.0;
            final isMatch = (curW - pw).abs() < 1e-2 && (curH - ph).abs() < 1e-2;

            return InkWell(
              onTap: () {
                _updateParam('width', pw);
                _updateParam('height', ph);
                _updateParam('port1_width', pw);
                _updateParam('port1_height', ph);
                _updateParam('port2_width', pw);
                _updateParam('port2_height', ph);
                _setControllerText('width', pw);
                _setControllerText('height', ph);
                _setControllerText('port1_width', pw);
                _setControllerText('port1_height', ph);
                _setControllerText('port2_width', pw);
                _setControllerText('port2_height', ph);
                setState(() {});
              },
              borderRadius: BorderRadius.circular(4),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
                decoration: BoxDecoration(
                  color: isMatch
                      ? const Color(0xFF0284C7).withValues(alpha: 0.2)
                      : (isLight ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B)),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isMatch
                        ? const Color(0xFF0284C7)
                        : (isLight ? const Color(0xFFCBD5E1) : const Color(0xFF475569)),
                    width: isMatch ? 1.2 : 0.8,
                  ),
                ),
                child: Text(
                  ps,
                  style: TextStyle(
                    fontSize: 11.0,
                    fontWeight: isMatch ? FontWeight.bold : FontWeight.w600,
                    color: isMatch
                        ? const Color(0xFF0284C7)
                        : (isLight ? const Color(0xFF1E293B) : Colors.white),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // --- Section 8: Physical Takeoff HUD ---
  Widget _buildTakeoffHUD() {
    final takeoff = widget.instance?.calculatedTakeoff;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0F1D),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF1E293B), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildTakeoffItem('BLANK AREA', takeoff != null ? '${takeoff.blankSurfaceAreaM2} m²' : '0.185 m²'),
          Container(width: 1, height: 26, color: const Color(0xFF1E293B)),
          _buildTakeoffItem('NET WEIGHT', takeoff != null ? '${takeoff.estimatedNetWeightKg} kg' : '1.45 kg'),
          Container(width: 1, height: 26, color: const Color(0xFF1E293B)),
          _buildTakeoffItem('GAUGE', '${_currentParams["thickness"] ?? 1.5} mm'),
        ],
      ),
    );
  }

  Widget _buildTakeoffItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9.5,
            color: Color(0xFF94A3B8),
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13.0,
            color: Color(0xFF00E5FF),
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
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
