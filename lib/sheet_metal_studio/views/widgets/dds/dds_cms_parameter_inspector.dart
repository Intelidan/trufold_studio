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

import '../../../engine/dds/dds_instance_evaluator.dart';
import '../../../engine/cms/tray_reducer_scaler.dart';
import '../../../models/cad_material_preset.dart';
import '../../../models/cms/cms_product_contract.dart';
import '../../../models/dds/dds_product_instance.dart';
import '../../../models/fold_bend_line.dart';
import '../../../models/sheet_metal_definition.dart';
import '../../../viewmodels/sheet_metal_studio_viewmodel.dart';
import '../../../engine/ladder/ladder_two_pitch_solver.dart';
import '../../../models/ladder/ladder_assembly_parameters.dart';
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
  final Map<String, FocusNode> _focusNodes = {};
  bool _arePortsLinked = false;
  bool _isFolded = false;
  final Map<String, double> _localParams = {};
  bool? _localCoverIncluded;
  String? _localMaterial;

  FocusNode _getFocusNode(String key) {
    return _focusNodes.putIfAbsent(key, () => FocusNode());
  }

  String get _currentMaterial => _localMaterial ?? widget.instance?.material ?? widget.viewModel?.document.material.materialGrade ?? 'Pre-Galv DX51D (GI)';

  static const List<_MaterialOption> _availableMaterials = [
    _MaterialOption('GI', 'Pre-Galv DX51D (GI)'),
    _MaterialOption('MS', 'Mild Steel CR4 (MS)'),
    _MaterialOption('HR', 'Hot Rolled Steel (HR)'),
    _MaterialOption('CRCA', 'Cold Rolled (CRCA)'),
    _MaterialOption('AL', 'Aluminium 5052 (AL)', isAluminium: true),
    _MaterialOption('SS304', 'Stainless Steel 304 (SS304)', isStainless: true),
    _MaterialOption('SS316', 'Stainless Steel 316 (SS316)', isStainless: true),
    _MaterialOption('HDG', 'Hot Dip Galvanized (HDG)'),
    _MaterialOption('PLASTIC', 'Engineering Plastic (Dielectric)', isPlastic: true),
  ];

  void _updateMaterial(String val) {
    setState(() {
      _localMaterial = val;
    });

    final density = DdsInstanceEvaluator.resolveDensity(val);
    final thk =
        ((_currentParams['thickness'] ?? widget.instance?.instanceParameters['thickness'] ?? widget.viewModel?.document.material.thicknessMm ?? 1.5) as num)
            .toDouble();

    if (widget.instance != null && widget.onInstanceChanged != null) {
      final oldTakeoff = widget.instance!.calculatedTakeoff;
      DdsCalculatedTakeoff? updatedTakeoff;
      if (oldTakeoff != null && oldTakeoff.blankSurfaceAreaM2 > 0) {
        final newWeight = oldTakeoff.blankSurfaceAreaM2 * (thk / 1000.0) * density;
        updatedTakeoff = oldTakeoff.copyWith(estimatedNetWeightKg: double.parse(newWeight.toStringAsFixed(2)));
      }
      widget.onInstanceChanged!(widget.instance!.copyWith(material: val, calculatedTakeoff: updatedTakeoff ?? oldTakeoff));
    }

    if (widget.viewModel != null) {
      final vm = widget.viewModel!;
      SheetMetalMaterialGrade? grade;
      CoatingFinish coating = CoatingFinish.none;

      if (val.contains('304')) {
        grade = SheetMetalMaterialGrade.ss304;
      } else if (val.contains('316')) {
        grade = SheetMetalMaterialGrade.ss316;
      } else if (val.contains('AL') || val.contains('Alum') || val.contains('5052')) {
        grade = SheetMetalMaterialGrade.aluminium;
      } else if (val.contains('HR')) {
        grade = SheetMetalMaterialGrade.hr;
      } else if (val.contains('CRCA')) {
        grade = SheetMetalMaterialGrade.crca;
      } else if (val.contains('MS') || val.contains('Mild')) {
        grade = SheetMetalMaterialGrade.ms;
      } else if (val.contains('HDG')) {
        grade = SheetMetalMaterialGrade.gi;
        coating = CoatingFinish.hdg;
      } else if (val.contains('GI') || val.contains('Galv')) {
        grade = SheetMetalMaterialGrade.gi;
      }

      if (grade != null) {
        vm.setMaterialDefinition(grade: grade, finish: coating);
      }
      vm.setMaterialGrade(val);

      // Synchronize 3D Shader Preset
      final preset = CadMaterialSettings.presetFromMaterialGrade(val);
      vm.updateGraphicsPreferences((prefs) => prefs.copyWith(
        materialSettings: CadMaterialSettings.preset(preset),
      ));
    }
  }

  void _updateShaderPreset(CadMaterialPresetType preset) {
    if (widget.viewModel == null) return;
    final vm = widget.viewModel!;

    vm.updateGraphicsPreferences((prefs) => prefs.copyWith(
      materialSettings: CadMaterialSettings.preset(preset),
    ));

    final gradeCode = CadMaterialSettings.preset(preset).toMaterialGradeCode();
    _MaterialOption? match;
    for (final opt in _availableMaterials) {
      if (opt.shortCode == gradeCode || opt.name.toUpperCase().contains(gradeCode)) {
        match = opt;
        break;
      }
    }
    if (match != null) {
      _updateMaterial(match.name);
    } else {
      vm.setMaterialGrade(gradeCode);
      setState(() {
        _localMaterial = gradeCode;
      });
    }
  }

  String? _lastDocFingerprint;

  void _resetLocalStateIfDocChanged() {
    final doc = widget.viewModel?.document;
    final fingerprint = widget.instance != null
        ? 'INSTANCE_${widget.instance!.instanceId}_${widget.instance!.productName}'
        : (doc != null ? 'DOC_${doc.itemName}_${doc.productType}_${identityHashCode(doc)}' : null);

    if (_lastDocFingerprint != null && _lastDocFingerprint != fingerprint) {
      _localParams.clear();
      _localCoverIncluded = null;
      _localMaterial = null;
      final scLinked = widget.viewModel?.scalingController?.isLinkedPorts;
      final pType = _productType;
      final isUnequal = pType == 'unequalCross' || pType == 'unequalTee' || pType == 'reducer';
      _arePortsLinked = scLinked ?? !isUnequal;
      _isFolded = false;
      _controllers.clear();
    }
    _lastDocFingerprint = fingerprint;
  }

  @override
  void initState() {
    super.initState();
    _controllers = {};
    _resetLocalStateIfDocChanged();
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
        _localParams.clear();
        _localCoverIncluded = null;
        _localMaterial = null;
        final scLinked = widget.viewModel?.scalingController?.isLinkedPorts;
        final pType = _productType;
        final isUnequal = pType == 'unequalCross' || pType == 'unequalTee' || pType == 'reducer';
        _arePortsLinked = scLinked ?? !isUnequal;
        _isFolded = false;
        _controllers.clear();
      }
    } else {
      oldWidget.viewModel?.removeListener(_onViewModelChanged);
    }
    _resetLocalStateIfDocChanged();
    if (oldWidget.instance != widget.instance || oldWidget.viewModel != widget.viewModel) {
      _syncControllers();
    }
  }

  @override
  void dispose() {
    widget.viewModel?.removeListener(_onViewModelChanged);
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final f in _focusNodes.values) {
      f.dispose();
    }
    super.dispose();
  }

  void _onViewModelChanged() {
    if (mounted) {
      _resetLocalStateIfDocChanged();
      setState(() {
        _syncControllers();
        _localCoverIncluded = widget.viewModel?.hasCover ?? (widget.viewModel?.document.cover != null);
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
      if ((item.contains('trunk') || pType.contains('trunk')) &&
          !item.contains('tray') &&
          !pType.contains('tray') &&
          !item.contains('ladder') &&
          !pType.contains('ladder')) {
        return true;
      }
    }
    return false;
  }

  bool get _isLadder {
    final cat = _currentCategory.toLowerCase();
    if (cat.contains('ladder')) return true;
    if (widget.instance != null) {
      final tId = widget.instance!.templateReference.templateId.toLowerCase();
      final pName = widget.instance!.productName.toLowerCase();
      if (tId.contains('ladder') || pName.contains('ladder')) return true;
    }
    if (widget.viewModel != null) {
      if (widget.viewModel!.isLadderAssembly) return true;
      final doc = widget.viewModel!.document;
      final item = doc.itemName.toLowerCase();
      final pType = doc.productType.toLowerCase();
      if (item.contains('ladder') || pType.contains('ladder')) return true;
      if (widget.viewModel!.detectedFittingMetadata?.isLadder == true) return true;
      if (doc.metadata['ladder_accessory_type'] != null) return true;
      if (doc.metadata['ladder_type'] != null) return true;
      if (doc.metadata['is_ladder_assembly'] == true) return true;
      if (doc.metadata['isLadderAssembly'] == true) return true;
    }
    return false;
  }

  bool get _isCableTray {
    if (_isLadder || _isTrunking) return false;
    final cat = _currentCategory.toLowerCase();
    if (cat.contains('tray')) return true;
    if (widget.instance != null) {
      final tId = widget.instance!.templateReference.templateId.toLowerCase();
      final pName = widget.instance!.productName.toLowerCase();
      if (tId.contains('tray') || pName.contains('tray')) return true;
    }
    if (widget.viewModel != null) {
      final doc = widget.viewModel!.document;
      final item = doc.itemName.toLowerCase();
      final pType = doc.productType.toLowerCase();
      if (item.contains('tray') || pType.contains('tray') || doc.category.toLowerCase().contains('tray')) return true;
    }
    return cat.contains('tray');
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
      if (tId.contains('inside_riser')) {
        return (tId.contains('90') || pType.contains('90')) ? CmsProductContract.insideRiser90 : CmsProductContract.insideRiser45;
      }
      if (tId.contains('outside_riser')) {
        return (tId.contains('90') || pType.contains('90')) ? CmsProductContract.outsideRiser90 : CmsProductContract.outsideRiser45;
      }
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
        final isUnequal =
            (ports[0].width - ports[1].width).abs() > 2 ||
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
      final lookupDoc =
          CmsProductContract.lookup(vm.document.productType, vm.document.itemName) ??
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
      result['coupler_flap_length'] = 90.0;
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
      // 5b. Fitting metadata parameters
      final fittingMeta = vm.document.metadata['fittingMetadata'];
      if (fittingMeta is Map && fittingMeta['parameters'] is Map) {
        final fParams = fittingMeta['parameters'] as Map;
        for (final entry in fParams.entries) {
          if (entry.value is num) {
            result[entry.key.toString()] ??= (entry.value as num).toDouble();
          }
        }
      }
      // 6. Base thickness & flange sizes
      result['thickness'] ??= vm.document.material.thicknessMm;
      result['base_flange_size'] ??= 20.0;
      result['flange_direction'] ??= (vm.document.parameters['flange_direction'] ?? 0.0);
      double? docFlangeAngle;
      for (final b in vm.document.bends) {
        if (b.role == BendLineRole.flange || b.id.toUpperCase().startsWith('FL') || b.layer.toUpperCase().contains('FLANGE')) {
          docFlangeAngle = b.targetAngleDeg;
          break;
        }
      }
      result['flange_angle'] ??= (vm.document.parameters['flange_angle'] ?? docFlangeAngle ?? 135.0);
      result['cover_flange_size'] ??= ((vm.document.cover?.properties['flangeDepthMm'] as num?)?.toDouble() ?? vm.coverFlangeDepth);

      // Coupler flaps & slots
      result['include_coupler_flaps'] ??= ((vm.scalingController?.includeCouplerFlaps ?? ((vm.document.parameters['include_coupler_flaps'] ?? 0.0) > 0.5))
          ? 1.0
          : 0.0);
      result['coupler_flap_length'] ??= (vm.scalingController?.couplerFlapLength ?? vm.document.parameters['coupler_flap_length'] ?? 90.0);
      result['coupler_slot_length'] ??= (vm.document.parameters['coupler_slot_length'] ?? 20.0);
      result['coupler_slot_width'] ??= (vm.document.parameters['coupler_slot_width'] ?? 9.0);
      result['coupler_slot_pitch'] ??= (vm.document.parameters['coupler_slot_pitch'] ?? 25.0);
      result['reducer_alignment'] ??= (vm.scalingController?.reducerAlignment == ReducerAlignment.left
          ? 1.0
          : (vm.scalingController?.reducerAlignment == ReducerAlignment.right ? 2.0 : 0.0));

      // 7. Bend angle & radius
      result['bend_angle'] ??= (vm.document.parameters['bend_angle'] ?? vm.document.parameters['angle'] ?? (_productType == 'flatBend45' ? 45.0 : 90.0));
      result['radius'] ??= (vm.document.parameters['radius'] ?? 180.0);

      // 8. Perforation controls
      result['has_perforations'] ??= 1.0;
      result['perforation_pitch'] ??= (vm.scalingController?.perforationPitch ?? 100.0);
      result['perforation_staggered'] ??= 1.0;
      result['perforation_slot_length'] ??= 30.0;
      result['perforation_slot_width'] ??= 7.0;

      // 9. Ladder Assembly parameters
      result['length'] ??= (vm.document.parameters['length'] ?? 3000.0);
      result['accessory_style'] ??=
          (vm.document.parameters['accessory_style'] ??
          (vm.document.metadata['ladderParameters'] is Map && (vm.document.metadata['ladderParameters'] as Map)['accessoryStyle'] == 'curved' ? 0.0 : 1.0));
      result['outsideWeldProjection'] ??=
          (vm.document.parameters['outsideWeldProjection'] ??
          vm.document.parameters['outside_weld_projection'] ??
          (vm.document.metadata['ladderParameters'] is Map
              ? ((vm.document.metadata['ladderParameters'] as Map)['outsideWeldProjection'] as num?)?.toDouble()
              : null) ??
          3.5);
      final rPitch = (result['rung_pitch'] ?? result['intermediateTargetPitch'] ?? result['rungPitch'] ?? 250.0);
      result['end_margin_pitch'] ??=
          (vm.document.parameters['end_margin_pitch'] ??
          vm.document.parameters['endMarginPitch'] ??
          (vm.document.metadata['ladderParameters'] is Map
              ? ((vm.document.metadata['ladderParameters'] as Map)['endMarginPitch'] as num?)?.toDouble()
              : null) ??
          (rPitch / 2.0));
    }
    // Overlay local reactive state for immediate 0ms UI feedback
    result.addAll(_localParams);
    return result;
  }

  void _syncControllers() {
    final sc = widget.viewModel?.scalingController;
    if (sc != null && sc.isLinkedPorts != _arePortsLinked) {
      _arePortsLinked = sc.isLinkedPorts;
    }
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
    _setControllerText('length', p['length'] ?? 3000.0);

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

    // Ladder two-pitch controllers
    final rungPitchVal = p['rung_pitch'] ?? p['intermediateTargetPitch'] ?? p['rungPitch'] ?? 250.0;
    _setControllerText('rung_pitch', rungPitchVal);
    final endMarginVal = p['end_margin_pitch'] ?? p['end_rung_offset'] ?? p['endMarginPitch'] ?? (rungPitchVal / 2.0);
    _setControllerText('end_margin_pitch', endMarginVal);
  }

  void _setControllerText(String key, double val) {
    if (_focusNodes[key]?.hasFocus == true) {
      return;
    }
    final text = key == 'thickness' ? val.toStringAsFixed(2) : (val % 1 == 0 ? val.toInt().toString() : val.toStringAsFixed(1));
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

    if (key == 'end_margin_pitch' || key == 'endMarginPitch' || key == 'end_rung_offset') {
      _localParams['end_margin_pitch'] = value;
      _localParams['endMarginPitch'] = value;
      _localParams['end_rung_offset'] = value;
      _setControllerText('end_margin_pitch', value);
    } else if (key == 'rung_pitch' || key == 'intermediateTargetPitch' || key == 'rungPitch') {
      _localParams['rung_pitch'] = value;
      _localParams['intermediateTargetPitch'] = value;
      _localParams['rungPitch'] = value;
      _setControllerText('rung_pitch', value);
    } else if (key == 'outsideWeldProjection' || key == 'outside_weld_projection') {
      _localParams['outsideWeldProjection'] = value;
      _localParams['outside_weld_projection'] = value;
      _setControllerText('outsideWeldProjection', value);
      _setControllerText('outside_weld_projection', value);
    }

    final updated = Map<String, double>.from(_currentParams);
    updated[key] = value;
    if (key == 'end_margin_pitch' || key == 'endMarginPitch' || key == 'end_rung_offset') {
      updated['end_margin_pitch'] = value;
      updated['endMarginPitch'] = value;
      updated['end_rung_offset'] = value;
    } else if (key == 'rung_pitch' || key == 'intermediateTargetPitch' || key == 'rungPitch') {
      updated['rung_pitch'] = value;
      updated['intermediateTargetPitch'] = value;
      updated['rungPitch'] = value;
    } else if (key == 'outsideWeldProjection' || key == 'outside_weld_projection') {
      updated['outsideWeldProjection'] = value;
      updated['outside_weld_projection'] = value;
    }

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
      var updatedInst = widget.instance!.copyWith(instanceParameters: updated);
      if (key == 'cover_flange_size') {
        updatedInst = updatedInst.copyWith(coverConfiguration: updatedInst.coverConfiguration.copyWith(flangeDepthMm: value));
      }
      if (key == 'bend_angle') {
        updated['angle'] = value;
      }
      widget.onInstanceChanged!(updatedInst);
    } else if (widget.viewModel != null) {
      final vm = widget.viewModel!;
      if (!_isLadder && vm.scalingController == null) {
        vm.startTeachScaling();
      }
      if (key == 'flange_direction') {
        vm.document.parameters['flange_direction'] = value;
      } else if (key == 'flange_angle') {
        vm.document.parameters['flange_angle'] = value;
      } else if (key == 'cover_flange_size') {
        vm.document.parameters['cover_flange_size'] = value;
        vm.setCoverFlangeDepth(value);
      } else if (key == 'include_coupler_flaps') {
        vm.document.parameters['include_coupler_flaps'] = value;
        vm.scalingController?.setIncludeCouplerFlaps(value > 0.5, animate: true);
      } else if (key == 'coupler_flap_length') {
        vm.document.parameters['coupler_flap_length'] = value;
        vm.scalingController?.setCouplerFlapLength(value);
      } else if (key == 'perforation_pitch') {
        vm.scalingController?.setPerforationPitch(value);
      } else if (key == 'radius') {
        vm.document.parameters['radius'] = value;
      } else if (key == 'reducer_alignment') {
        final align = value == 1.0 ? ReducerAlignment.left : (value == 2.0 ? ReducerAlignment.right : ReducerAlignment.straight);
        vm.scalingController?.setReducerAlignment(align);
      }

      if (_arePortsLinked) {
        if (key.endsWith('_width') || key == 'width') {
          vm.applyCmsMorphParameter('width', value);
        } else if (key.endsWith('_height') || key == 'height') {
          vm.applyCmsMorphParameter('height', value);
        }
      }
      if (key == 'outsideWeldProjection' || key == 'outside_weld_projection') {
        vm.applyCmsMorphParameter('outsideWeldProjection', value);
        vm.applyCmsMorphParameter('outside_weld_projection', value);
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
    _localParams.clear();
    double baseW = 100.0;
    double baseH = 50.0;

    final vm = widget.viewModel;
    if (vm != null) {
      if (vm.scalingController != null) {
        final ctrl = vm.scalingController!;
        baseW = ctrl.model.parameters['width']?.baselineValue ?? (ctrl.baselinePorts.isNotEmpty ? ctrl.baselinePorts.first.nominalWidth : 100.0);
        baseH = ctrl.model.parameters['height']?.baselineValue ?? (ctrl.baselinePorts.isNotEmpty ? ctrl.baselinePorts.first.nominalHeight : 50.0);

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
          // Coupler slots and flaps are only required for Cable tray items and no other categories
          if (_isCableTray) ...[
            _buildSectionHeader('2. COUPLER SLOTS & FLAPS', Icons.more_horiz, null),
            const SizedBox(height: 6),
            _buildCouplerSlotsSection(),
            const SizedBox(height: 12),
          ],

          // --- Section 3: Floor Bed Perforations OR Ladder Rungs & Joints ---
          if (_isLadder) ...[
            _buildSectionHeader('3. LADDER RUNGS & WELDING JOINT', Icons.format_line_spacing, null),
            const SizedBox(height: 6),
            _buildLadderRungAndJointSection(),
            const SizedBox(height: 12),
          ] else ...[
            _buildSectionHeader('3. FLOOR PERFORATIONS & STAMPING', Icons.grid_view, null),
            const SizedBox(height: 6),
            _buildFloorPerforationsSection(),
            const SizedBox(height: 12),
          ],

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
              label: const Text('Bake & Sync Dimensions', style: TextStyle(fontSize: 13.0, fontWeight: FontWeight.bold, letterSpacing: 0.4)),
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
        final panelWidth = widget.isDetached ? 400.0 : (hasFiniteWidth ? double.infinity : 395.0);

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
                    border: Border(bottom: BorderSide(color: isLight ? const Color(0xFFE2E8F0) : const Color(0xFF334155), width: 1.0)),
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
                              style: TextStyle(color: Colors.white, fontSize: 13.0, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              '${_formatProductTitle(pType)} • Live Morph Engine',
                              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.0, fontWeight: FontWeight.w500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (widget.isDetached) ...[
                        IconButton(
                          icon: Icon(_isFolded ? Icons.unfold_more : Icons.unfold_less, size: 18, color: Colors.white70),
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
                              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                              child: const Icon(Icons.chevron_right, size: 18, color: Colors.white),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (widget.onDetach != null)
                        IconButton(
                          icon: Icon(widget.isDetached ? Icons.vertical_align_bottom : Icons.open_in_new, size: 17, color: Colors.white70),
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
                    constraints: BoxConstraints(maxHeight: (MediaQuery.of(context).size.height - 120).clamp(300.0, 720.0)),
                    child: scrollBody,
                  )
                else
                  Expanded(child: scrollBody),
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
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDynamicPortEditors(String pType) {
    if (pType == 'unequalCross') {
      // 4 Ports for Unequal Cross (West, North, East, South)
      return Column(
        children: [
          _buildPortRow('P1', 'Port 1 (West)', 'port1_width', 'port1_height', const Color(0xFF0284C7)),
          const SizedBox(height: 6),
          _buildPortRow('P2', 'Port 2 (North)', 'port2_width', 'port2_height', const Color(0xFF059669)),
          const SizedBox(height: 6),
          _buildPortRow('P3', 'Port 3 (East)', 'port3_width', 'port3_height', const Color(0xFFD97706)),
          const SizedBox(height: 6),
          _buildPortRow('P4', 'Port 4 (South)', 'port4_width', 'port4_height', const Color(0xFF7C3AED)),
          if (_isLadder) _buildLadderAccessoryStyleToggle(),
        ],
      );
    } else if (pType == 'equalCross') {
      // Equal Cross: 1 common port setting
      return Column(
        children: [_buildPortRow('P1-4', '4 Equal Cross Ports', 'width', 'height', const Color(0xFF0284C7)), if (_isLadder) _buildLadderAccessoryStyleToggle()],
      );
    } else if (pType == 'unequalTee') {
      // Unequal Tee: 3 distinct ports (P1 Branch, P2 Right, P3 Main)
      return Column(
        children: [
          _buildPortRow('P1', 'Port 1 (Branch)', 'port1_width', 'port1_height', const Color(0xFF7C3AED)),
          const SizedBox(height: 6),
          _buildPortRow('P2', 'Port 2 (Right)', 'port2_width', 'port2_height', const Color(0xFF059669)),
          const SizedBox(height: 6),
          _buildPortRow('P3', 'Port 3 (Main)', 'port3_width', 'port3_height', const Color(0xFF0284C7)),
          if (_isLadder) _buildLadderAccessoryStyleToggle(),
        ],
      );
    } else if (pType == 'equalTee') {
      // Equal Tee: 3 Equal Ports (W × H)
      return Column(
        children: [
          _buildPortRow('TEE', '3 Equal Ports (W × H)', 'width', 'height', const Color(0xFF0284C7)),
          if (_isLadder) _buildLadderAccessoryStyleToggle(),
        ],
      );
    } else if (pType == 'reducer') {
      // Reducer: Port 1 (Inlet) + Port 2 (Outlet) + Alignment Selection
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPortRow('INLET', 'Port 1 (Large Inlet)', 'port1_width', 'port1_height', const Color(0xFF0284C7)),
          const SizedBox(height: 6),
          _buildPortRow('OUTLET', 'Port 2 (Small Outlet)', 'port2_width', 'port2_height', const Color(0xFF059669)),
          const SizedBox(height: 8),
          _buildReducerAlignmentToggle(),
        ],
      );
    } else {
      // Bends, Risers, Straight
      final isRiser = pType == 'insideRiser' || pType == 'outsideRiser';
      final isBend =
          (pType == 'flatBend45' ||
              pType == 'flatBend90' ||
              pType.contains('bend') ||
              ((_currentParams.containsKey('bend_angle') || _currentParams.containsKey('radius')) && pType != 'straight')) &&
          !isRiser;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPortRow(
            isRiser ? 'RISER MOUTH' : (isBend ? 'BEND MOUTH' : (_isLadder ? 'LADDER SPAN' : 'MOUTH')),
            _isLadder ? 'Cable Ladder Span (Rung Span W × Rail H)' : (_isTrayOrLadder ? 'Cable Tray Mouth (W × H)' : 'Trunking Mouth (W × H)'),
            'width',
            'height',
            const Color(0xFF0284C7),
          ),
          if (_isLadder && !isBend && !isRiser) ...[const SizedBox(height: 8), _buildStraightLadderLengthRow()],
          if (isBend || isRiser) ...[const SizedBox(height: 8), _buildBendAngleAndRadiusSection(isRiser: isRiser)],
          if (_isLadder && (isBend || isRiser)) ...[_buildLadderAccessoryStyleToggle()],
        ],
      );
    }
  }

  Widget _buildLadderAccessoryStyleToggle() {
    final isLight = widget.isLightTheme;
    final styleVal = _currentParams['accessory_style'] ?? 1.0;
    final isSegmented = styleVal >= 0.5;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
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
                decoration: BoxDecoration(color: const Color(0xFF0D9488), borderRadius: BorderRadius.circular(4)),
                child: const Text(
                  'ACCESSORY PROFILE',
                  style: TextStyle(color: Colors.white, fontSize: 10.0, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Angular / Segmented vs Curved',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: isLight ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _buildDirectionOption(
                  title: 'Angular / Segmented',
                  subtitle: 'Mitered Facets (ISO Standard)',
                  icon: Icons.architecture,
                  isSelected: isSegmented,
                  onTap: () {
                    setState(() {
                      _localParams['accessory_style'] = 1.0;
                    });
                    _updateParam('accessory_style', 1.0);
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildDirectionOption(
                  title: 'Curved',
                  subtitle: 'Smooth Radial Sweep',
                  icon: Icons.rounded_corner,
                  isSelected: !isSegmented,
                  onTap: () {
                    setState(() {
                      _localParams['accessory_style'] = 0.0;
                    });
                    _updateParam('accessory_style', 0.0);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStraightLadderLengthRow() {
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
                decoration: BoxDecoration(color: const Color(0xFF0284C7), borderRadius: BorderRadius.circular(4)),
                child: const Text(
                  'LENGTH (L)',
                  style: TextStyle(color: Colors.white, fontSize: 10.0, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Straight Cable Ladder Standard Run',
                  style: TextStyle(fontSize: 12.0, fontWeight: FontWeight.bold, color: isLight ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _buildStepperField('L (mm)', 'length', 500.0, 6000.0, step: 100.0, presetSizes: const [1000, 1500, 2000, 2400, 3000, 6000]),
        ],
      ),
    );
  }

  Widget _buildReducerAlignmentToggle() {
    final alignVal = _currentParams['reducer_alignment'] ?? 0.0;
    final isStraight = alignVal == 0.0;
    final isLeft = alignVal == 1.0;
    final isRight = alignVal == 2.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, top: 4),
          child: Text(
            'REDUCER ALIGNMENT',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: widget.isLightTheme ? const Color(0xFF475569) : const Color(0xFF94A3B8),
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _buildDirectionOption(
                title: 'Concentric',
                subtitle: 'Straight Center',
                icon: Icons.compress,
                isSelected: isStraight,
                onTap: () {
                  setState(() {
                    _localParams['reducer_alignment'] = 0.0;
                  });
                  _updateParam('reducer_alignment', 0.0);
                },
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildDirectionOption(
                title: 'Left Reducer',
                subtitle: 'Straight Left (0°)',
                icon: Icons.align_horizontal_left,
                isSelected: isLeft,
                onTap: () {
                  setState(() {
                    _localParams['reducer_alignment'] = 1.0;
                  });
                  _updateParam('reducer_alignment', 1.0);
                },
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildDirectionOption(
                title: 'Right Reducer',
                subtitle: 'Straight Right (0°)',
                icon: Icons.align_horizontal_right,
                isSelected: isRight,
                onTap: () {
                  setState(() {
                    _localParams['reducer_alignment'] = 2.0;
                  });
                  _updateParam('reducer_alignment', 2.0);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBendAngleAndRadiusSection({bool isRiser = false}) {
    final isLight = widget.isLightTheme;
    final curRadius = _currentParams['radius'] ?? 180.0;
    final curAngle = _currentParams['bend_angle'] ?? (_currentParams['angle'] ?? (_productType == 'flatBend45' ? 45.0 : 90.0));
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
                  style: TextStyle(fontSize: 12.0, fontWeight: FontWeight.bold, color: isLight ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${curAngle.toStringAsFixed(0)}°',
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Color(0xFF7C3AED)),
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
                    style: TextStyle(fontSize: 12.0, fontWeight: FontWeight.bold, color: isLight ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${curRadius.toStringAsFixed(0)} mm',
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
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
                Text(
                  '100',
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: isLight ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
                ),
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
                Text(
                  '900',
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: isLight ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
                ),
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
                          color: (curRadius - preset).abs() < 1e-3 ? const Color(0xFF0284C7) : (isLight ? const Color(0xFFCBD5E1) : const Color(0xFF475569)),
                          width: (curRadius - preset).abs() < 1e-3 ? 1.2 : 0.6,
                        ),
                      ),
                      child: Text(
                        '${preset.toStringAsFixed(0)} mm',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: (curRadius - preset).abs() < 1e-3 ? FontWeight.bold : FontWeight.w500,
                          color: (curRadius - preset).abs() < 1e-3 ? const Color(0xFF0284C7) : (isLight ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
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
                  style: TextStyle(fontSize: 12.0, fontWeight: FontWeight.bold, color: isLight ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
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
              Expanded(child: _buildStepperField('H (mm)', heightKey, 25.0, 250.0, step: 25.0, presetSizes: const [25, 38, 50, 75, 100, 150, 200, 250])),
            ],
          ),
          if (_isLadder) ...[
            const SizedBox(height: 5),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'W = Rung Cut Length (Cable Span)',
                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: isLight ? const Color(0xFF0284C7) : const Color(0xFF38BDF8)),
                  ),
                ),
                Expanded(
                  child: Text(
                    'H = Side Rail Flat Width (Erected)',
                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: isLight ? const Color(0xFF059669) : const Color(0xFF34D399)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStepperField(String label, String key, double min, double max, {double step = 10.0, int decimals = 0, List<double>? presetSizes}) {
    final isLight = widget.isLightTheme;
    final ctrl = _controllers[key] ?? TextEditingController(text: '100');

    // Clean, compact badge text
    String badgeText = label;
    if (label.contains('(')) {
      badgeText = label.split('(').first.trim();
    }
    if (badgeText.toLowerCase() == 'thickness') badgeText = 'THK';
    if (badgeText.toLowerCase() == 'cover flange') badgeText = 'FLG';

    return LayoutBuilder(
      builder: (context, constraints) {
        final showBadge = constraints.maxWidth >= 70;
        final showSteppers = constraints.maxWidth >= 135;
        final showPresets = constraints.maxWidth >= 105 && presetSizes != null && presetSizes.isNotEmpty;

        return ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Container(
            height: 34,
            decoration: BoxDecoration(
              color: isLight ? Colors.white : const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: isLight ? const Color(0xFFCBD5E1) : const Color(0xFF475569), width: 0.9),
            ),
            child: Row(
              children: [
                // Integrated prefix badge inside container
                if (showBadge)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                    margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
                    decoration: BoxDecoration(color: isLight ? const Color(0xFFF1F5F9) : const Color(0xFF334155), borderRadius: BorderRadius.circular(3)),
                    child: Text(
                      badgeText,
                      style: TextStyle(fontSize: 10.0, fontWeight: FontWeight.bold, color: isLight ? const Color(0xFF475569) : const Color(0xFF94A3B8)),
                    ),
                  ),
                Expanded(
                  child: TextField(
                    controller: ctrl,
                    focusNode: _getFocusNode(key),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: TextStyle(fontSize: 12.0, fontWeight: FontWeight.bold, color: isLight ? const Color(0xFF0F172A) : Colors.white),
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(contentPadding: EdgeInsets.zero, isDense: true, border: InputBorder.none),
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
                if (showSteppers) ...[
                  // Stepper -
                  InkWell(
                    onTap: () {
                      final current = double.tryParse(ctrl.text) ?? 100.0;
                      final next = (current - step).clamp(min, max);
                      ctrl.text = decimals == 0 ? next.toStringAsFixed(0) : next.toStringAsFixed(decimals);
                      _updateParam(key, next);
                    },
                    child: Container(
                      width: 18,
                      height: 32,
                      alignment: Alignment.center,
                      child: Icon(Icons.remove, size: 13, color: isLight ? const Color(0xFF475569) : const Color(0xFF94A3B8)),
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
                      width: 18,
                      height: 32,
                      alignment: Alignment.center,
                      child: Icon(Icons.add, size: 13, color: isLight ? const Color(0xFF475569) : const Color(0xFF94A3B8)),
                    ),
                  ),
                ],
                // Compact Dropdown for standard common sizes
                if (showPresets)
                  PopupMenuButton<double>(
                    tooltip: 'Common standard sizes',
                    padding: EdgeInsets.zero,
                    child: Container(
                      width: 16,
                      height: 32,
                      alignment: Alignment.center,
                      child: const Icon(Icons.arrow_drop_down, size: 15, color: Color(0xFF0284C7)),
                    ),
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
        );
      },
    );
  }

  // --- Section 2: Coupler Slots & Flaps ---
  Widget _buildCouplerSlotsSection() {
    final isLight = widget.isLightTheme;
    final hasFlaps = (_currentParams['include_coupler_flaps'] ?? 0.0) > 0.5;
    final flapLen = _currentParams['coupler_flap_length'] ?? 30.0;

    final portH = _currentParams['port_height'] ?? _currentParams['height'] ?? _currentParams['port1_height'] ?? 50.0;
    final dynamicSlotLen = (portH - 20.0).clamp(10.0, 500.0).toStringAsFixed(0);

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
              Expanded(child: _buildStepperField('Slot L', 'coupler_slot_length', 10.0, 40.0, step: 5.0, presetSizes: const [15, 20, 25, 30])),
              const SizedBox(width: 8),
              Expanded(child: _buildStepperField('Slot W', 'coupler_slot_width', 5.0, 16.0, step: 1.0, presetSizes: const [7, 9, 11, 13])),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: _buildStepperField('Pitch', 'coupler_slot_pitch', 15.0, 50.0, step: 5.0, presetSizes: const [20, 25, 30, 35, 40])),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.4), width: 0.8),
                ),
                child: Text(
                  '3 VERTICAL SLOTS ($dynamicSlotLen×8mm)',
                  style: const TextStyle(fontSize: 10.0, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                ),
              ),
            ],
          ),
          // Prominent Coupler Flap Addition Action Button for Trays (Coupler flaps not needed for ladders)
          if (!_isLadder) ...[
            const SizedBox(height: 10),
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
                  color: hasFlaps ? const Color(0xFF4F46E5).withValues(alpha: 0.18) : (isLight ? Colors.white : const Color(0xFF1E293B)),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: hasFlaps ? const Color(0xFF6366F1) : (isLight ? const Color(0xFFCBD5E1) : const Color(0xFF475569)),
                    width: hasFlaps ? 1.5 : 1.0,
                  ),
                  boxShadow: hasFlaps ? [BoxShadow(color: const Color(0xFF6366F1).withValues(alpha: 0.25), blurRadius: 6, offset: const Offset(0, 2))] : null,
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
                                ? 'Integrated cheek tabs with 3× vertical slots • ${flapLen.toStringAsFixed(0)} mm'
                                : 'Add integrated folding connection flaps to port cheek walls',
                            style: TextStyle(fontSize: 10.0, color: isLight ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
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
                        style: TextStyle(fontSize: 10.0, fontWeight: FontWeight.bold, color: hasFlaps ? Colors.white : const Color(0xFF6366F1)),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (hasFlaps) ...[
              const SizedBox(height: 8),
              _buildStepperField('Flap Length (mm)', 'coupler_flap_length', 20.0, 150.0, step: 5.0, presetSizes: const [60, 75, 90, 100, 120]),
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [60.0, 75.0, 90.0, 100.0, 120.0].map((preset) {
                  final isCur = (flapLen - preset).abs() < 1e-3;
                  return InkWell(
                    onTap: () => _updateParam('coupler_flap_length', preset),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: isCur ? const Color(0xFF6366F1).withValues(alpha: 0.2) : (isLight ? Colors.white : const Color(0xFF1E293B)),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isCur ? const Color(0xFF6366F1) : (isLight ? const Color(0xFFCBD5E1) : const Color(0xFF475569)),
                          width: isCur ? 1.0 : 0.6,
                        ),
                      ),
                      child: Text(
                        '${preset.toStringAsFixed(0)} mm',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: isCur ? FontWeight.bold : FontWeight.w500,
                          color: isCur ? const Color(0xFF6366F1) : (isLight ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ],
      ),
    );
  }

  // --- Section 3: Ladder Rungs & Welding Joint ---
  Widget _buildLadderRungAndJointSection() {
    final isLight = widget.isLightTheme;
    final jointVal = _currentParams['rung_joint_method'] ?? 1.0;
    final isPassThrough = jointVal >= 0.5;
    final endMargin = _currentParams['end_margin_pitch'] ?? _currentParams['endMarginPitch'] ?? _currentParams['end_rung_offset'] ?? 75.0;
    final targetPitch = _currentParams['rung_pitch'] ?? _currentParams['intermediateTargetPitch'] ?? _currentParams['rungPitch'] ?? 250.0;
    final isFixedPitch = (_currentParams['rung_pitch_mode'] ?? 0.0) == 1.0;
    final projection = _currentParams['outsideWeldProjection'] ?? 3.5;
    final curWidth = _currentParams['width'] ?? 600.0;
    final curLength = _currentParams['length'] ?? 3000.0;
    final curThick = _currentParams['thickness'] ?? 2.0;

    // Solve live pattern
    final ladderParams = LadderAssemblyParameters(
      width: curWidth,
      length: curLength,
      thickness: curThick,
      endMarginPitch: endMargin,
      intermediateTargetPitch: targetPitch,
      pitchMode: isFixedPitch ? RungPitchMode.fixedPitch : RungPitchMode.equalizedPitch,
      jointMethod: isPassThrough ? LadderRungJointMethod.passThroughOutsideWeld : LadderRungJointMethod.directInsideWeld,
      outsideWeldProjection: projection,
    );
    final pitchResult = LadderTwoPitchSolver.solve(ladderParams);
    final cutLength = ladderParams.physicalRungCutLength;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isLight ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isLight ? const Color(0xFFE2E8F0) : const Color(0xFF334155), width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Joint Method Title & Live Cut Length Pill
          Row(
            children: [
              Expanded(
                child: Text(
                  'RUNG JOINT / WELDING METHOD',
                  style: TextStyle(
                    fontSize: 11.0,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: isLight ? const Color(0xFF475569) : const Color(0xFF94A3B8),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(color: isPassThrough ? const Color(0xFF0284C7) : const Color(0xFF059669), borderRadius: BorderRadius.circular(4)),
                child: Text(
                  'Cut L: ${cutLength.toStringAsFixed(1)} mm',
                  style: const TextStyle(color: Colors.white, fontSize: 10.0, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Row 2: Joint Selection Segmented Buttons
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () {
                    _updateParam('rung_joint_method', 0.0);
                  },
                  borderRadius: BorderRadius.circular(5),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                    decoration: BoxDecoration(
                      color: !isPassThrough
                          ? (isLight ? const Color(0xFFE0F2FE) : const Color(0xFF0369A1).withValues(alpha: 0.4))
                          : (isLight ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B)),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: !isPassThrough ? const Color(0xFF0284C7) : Colors.transparent, width: 1.5),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.arrow_downward,
                          size: 16,
                          color: !isPassThrough ? const Color(0xFF0284C7) : (isLight ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Direct Inside',
                          style: TextStyle(
                            fontSize: 11.0,
                            fontWeight: !isPassThrough ? FontWeight.bold : FontWeight.normal,
                            color: !isPassThrough ? const Color(0xFF0284C7) : (isLight ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                          ),
                        ),
                        Text('Flush / Solid Rail', style: TextStyle(fontSize: 9.0, color: isLight ? const Color(0xFF64748B) : const Color(0xFF94A3B8))),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () {
                    _updateParam('rung_joint_method', 1.0);
                  },
                  borderRadius: BorderRadius.circular(5),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                    decoration: BoxDecoration(
                      color: isPassThrough
                          ? (isLight ? const Color(0xFFE0F2FE) : const Color(0xFF0369A1).withValues(alpha: 0.4))
                          : (isLight ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B)),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: isPassThrough ? const Color(0xFF0284C7) : Colors.transparent, width: 1.5),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.open_in_new,
                          size: 16,
                          color: isPassThrough ? const Color(0xFF0284C7) : (isLight ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Pass-Through',
                          style: TextStyle(
                            fontSize: 11.0,
                            fontWeight: isPassThrough ? FontWeight.bold : FontWeight.normal,
                            color: isPassThrough ? const Color(0xFF0284C7) : (isLight ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                          ),
                        ),
                        Text('Punched Slot + Outer Weld', style: TextStyle(fontSize: 9.0, color: isLight ? const Color(0xFF64748B) : const Color(0xFF94A3B8))),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          if (isPassThrough) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Outside Projection: ${projection.toStringAsFixed(1)} mm',
                    style: TextStyle(fontSize: 11.0, color: isLight ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                  ),
                ),
                ...[5.0, 10.0, 15.0].map((proj) {
                  final isSel = (projection - proj).abs() < 0.1;
                  return InkWell(
                    onTap: () => _updateParam('outsideWeldProjection', proj),
                    child: Container(
                      margin: const EdgeInsets.only(left: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: isSel ? const Color(0xFF0284C7) : (isLight ? const Color(0xFFE2E8F0) : const Color(0xFF334155)),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        '${proj.toInt()}mm',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                          color: isSel ? Colors.white : (isLight ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ],

          const Divider(height: 18),

          // Two-Pitch Engine Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'TWO-PITCH ENGINE',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: isLight ? const Color(0xFF475569) : const Color(0xFF94A3B8)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF059669).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF059669), width: 0.8),
                ),
                child: Text(
                  '${pitchResult.rungCount} Rungs @ ${pitchResult.actualIntermediatePitch.toStringAsFixed(1)}mm',
                  style: const TextStyle(color: Color(0xFF059669), fontSize: 10.0, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // End Margin Pitch (P_end)
          Row(
            children: [
              SizedBox(
                width: 112,
                child: Text('End Margin (P_end):', style: TextStyle(fontSize: 11.0, color: isLight ? const Color(0xFF334155) : const Color(0xFFCBD5E1))),
              ),
              Container(
                width: 62,
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: isLight ? Colors.white : const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: isLight ? const Color(0xFFCBD5E1) : const Color(0xFF475569), width: 0.9),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controllers['end_margin_pitch'] ??= TextEditingController(text: endMargin.round().toString()),
                        focusNode: _getFocusNode('end_margin_pitch'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: TextStyle(fontSize: 11.0, fontWeight: FontWeight.bold, color: isLight ? const Color(0xFF0F172A) : Colors.white),
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(contentPadding: EdgeInsets.zero, isDense: true, border: InputBorder.none),
                        onChanged: (val) {
                          final parsed = double.tryParse(val);
                          if (parsed != null && parsed >= 10.0 && parsed <= 1000.0) {
                            _updateParam('end_margin_pitch', parsed);
                          }
                        },
                        onSubmitted: (val) {
                          final parsed = double.tryParse(val);
                          if (parsed != null && parsed >= 10.0 && parsed <= 1000.0) {
                            _updateParam('end_margin_pitch', parsed);
                          }
                        },
                      ),
                    ),
                    Text('mm', style: TextStyle(fontSize: 9.0, color: isLight ? const Color(0xFF64748B) : const Color(0xFF94A3B8))),
                  ],
                ),
              ),
              const Spacer(),
              ...[50.0, 75.0, 100.0].map((preset) {
                final isSel = (endMargin - preset).abs() < 0.5;
                return InkWell(
                  onTap: () {
                    _updateParam('end_margin_pitch', preset);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(left: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: isSel ? const Color(0xFF059669) : (isLight ? const Color(0xFFE2E8F0) : const Color(0xFF334155)),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      '${preset.round()}',
                      style: TextStyle(
                        fontSize: 10.0,
                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                        color: isSel ? Colors.white : (isLight ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
          const SizedBox(height: 6),

          // Target Intermediate Pitch (P_target)
          Row(
            children: [
              SizedBox(
                width: 112,
                child: Text('Body Pitch (P_target):', style: TextStyle(fontSize: 11.0, color: isLight ? const Color(0xFF334155) : const Color(0xFFCBD5E1))),
              ),
              Container(
                width: 62,
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: isLight ? Colors.white : const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: isLight ? const Color(0xFFCBD5E1) : const Color(0xFF475569), width: 0.9),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controllers['rung_pitch'] ??= TextEditingController(text: targetPitch.round().toString()),
                        focusNode: _getFocusNode('rung_pitch'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: TextStyle(fontSize: 11.0, fontWeight: FontWeight.bold, color: isLight ? const Color(0xFF0F172A) : Colors.white),
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(contentPadding: EdgeInsets.zero, isDense: true, border: InputBorder.none),
                        onChanged: (val) {
                          final parsed = double.tryParse(val);
                          if (parsed != null && parsed >= 50.0 && parsed <= 2000.0) {
                            _updateParam('rung_pitch', parsed);
                          }
                        },
                        onSubmitted: (val) {
                          final parsed = double.tryParse(val);
                          if (parsed != null && parsed >= 50.0 && parsed <= 2000.0) {
                            _updateParam('rung_pitch', parsed);
                          }
                        },
                      ),
                    ),
                    Text('mm', style: TextStyle(fontSize: 9.0, color: isLight ? const Color(0xFF64748B) : const Color(0xFF94A3B8))),
                  ],
                ),
              ),
              const Spacer(),
              ...[150.0, 200.0, 250.0, 300.0].map((preset) {
                final isSel = (targetPitch - preset).abs() < 0.5;
                return InkWell(
                  onTap: () {
                    _updateParam('rung_pitch', preset);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(left: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: isSel ? const Color(0xFF059669) : (isLight ? const Color(0xFFE2E8F0) : const Color(0xFF334155)),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      '${preset.round()}',
                      style: TextStyle(
                        fontSize: 10.0,
                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                        color: isSel ? Colors.white : (isLight ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
          const SizedBox(height: 6),

          // Pitch Mode Toggle (Equalized vs Fixed)
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _updateParam('rung_pitch_mode', 0.0),
                  child: Row(
                    children: [
                      Icon(
                        !isFixedPitch ? Icons.radio_button_checked : Icons.radio_button_off,
                        size: 15,
                        color: !isFixedPitch ? const Color(0xFF059669) : Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text('Equalized Pitch', style: TextStyle(fontSize: 10.5, fontWeight: !isFixedPitch ? FontWeight.bold : FontWeight.normal)),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: () => _updateParam('rung_pitch_mode', 1.0),
                  child: Row(
                    children: [
                      Icon(
                        isFixedPitch ? Icons.radio_button_checked : Icons.radio_button_off,
                        size: 15,
                        color: isFixedPitch ? const Color(0xFF059669) : Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text('Fixed Pitch', style: TextStyle(fontSize: 10.5, fontWeight: isFixedPitch ? FontWeight.bold : FontWeight.normal)),
                    ],
                  ),
                ),
              ),
            ],
          ),
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
                decoration: BoxDecoration(color: hasPerf ? const Color(0xFF059669) : const Color(0xFF64748B), borderRadius: BorderRadius.circular(4)),
                child: Text(
                  hasPerf ? 'ACTIVE' : 'SOLID',
                  style: const TextStyle(color: Colors.white, fontSize: 10.0, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Floor Bed Perforations',
                  style: TextStyle(fontSize: 12.0, fontWeight: FontWeight.bold, color: isLight ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
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
                    style: TextStyle(fontSize: 11.0, fontWeight: FontWeight.w600, color: isLight ? const Color(0xFF475569) : const Color(0xFF94A3B8)),
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
                Expanded(child: _buildStepperField('Slot L', 'perforation_slot_length', 15.0, 50.0, step: 5.0, decimals: 0)),
                const SizedBox(width: 8),
                Expanded(child: _buildStepperField('Slot W', 'perforation_slot_width', 5.0, 15.0, step: 1.0, decimals: 0)),
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
                          color: isStaggered ? const Color(0xFF0284C7).withValues(alpha: 0.18) : (isLight ? Colors.white : const Color(0xFF1E293B)),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: isStaggered ? const Color(0xFF0284C7) : (isLight ? const Color(0xFFCBD5E1) : const Color(0xFF475569)),
                            width: isStaggered ? 1.2 : 0.7,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.grain, size: 14, color: isStaggered ? const Color(0xFF0284C7) : Colors.grey),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                'Staggered (Zig-Zag)',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: isStaggered ? FontWeight.bold : FontWeight.w500,
                                  color: isStaggered ? const Color(0xFF0284C7) : (isLight ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                                ),
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
                          color: !isStaggered ? const Color(0xFF0284C7).withValues(alpha: 0.18) : (isLight ? Colors.white : const Color(0xFF1E293B)),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: !isStaggered ? const Color(0xFF0284C7) : (isLight ? const Color(0xFFCBD5E1) : const Color(0xFF475569)),
                            width: !isStaggered ? 1.2 : 0.7,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.view_comfy, size: 14, color: !isStaggered ? const Color(0xFF0284C7) : Colors.grey),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                'Inline (Uniform Grid)',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: !isStaggered ? FontWeight.bold : FontWeight.w500,
                                  color: !isStaggered ? const Color(0xFF0284C7) : (isLight ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                                ),
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
                        Flexible(
                          child: Text(
                            'Open Pattern Stamping Tool...',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11.0, fontWeight: FontWeight.bold, color: isLight ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
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
                style: TextStyle(fontSize: 10.5, fontStyle: FontStyle.italic, color: isLight ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --- Section 4: Flange Direction Toggle & Angle Selector ---
  Widget _buildFlangeDirectionToggle() {
    final isInside = (_currentParams['flange_direction'] ?? 0.0) == 0.0;
    double? docFlangeAngle;
    if (widget.viewModel != null) {
      for (final b in widget.viewModel!.document.bends) {
        if (b.role == BendLineRole.flange || b.id.toUpperCase().startsWith('FL') || b.layer.toUpperCase().contains('FLANGE')) {
          docFlangeAngle = b.targetAngleDeg;
          break;
        }
      }
    }
    final curAngle = _currentParams['flange_angle'] ?? docFlangeAngle ?? 135.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildDirectionOption(
                title: 'Inside Flange',
                subtitle: 'Return Lip (${curAngle.toStringAsFixed(0)}°)',
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
                subtitle: 'Exterior Lip (${curAngle.toStringAsFixed(0)}°)',
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
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: widget.isLightTheme ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A).withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: widget.isLightTheme ? const Color(0xFFE2E8F0) : const Color(0xFF334155), width: 0.8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'FLANGE BEND ANGLE',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  color: widget.isLightTheme ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                  letterSpacing: 0.5,
                ),
              ),
              Row(
                children: [90.0, 135.0].map((angle) {
                  final isSelected = (curAngle - angle).abs() < 1e-2;
                  return Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () {
                        setState(() {
                          _localParams['flange_angle'] = angle;
                        });
                        _updateParam('flange_angle', angle);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF0284C7).withValues(alpha: 0.15)
                              : (widget.isLightTheme ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B)),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: isSelected ? const Color(0xFF0284C7) : Colors.transparent, width: 1.0),
                        ),
                        child: Text(
                          '${angle.toStringAsFixed(0)}°',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isSelected ? const Color(0xFF0284C7) : (widget.isLightTheme ? const Color(0xFF334155) : const Color(0xFF94A3B8)),
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
                ? const LinearGradient(colors: [Color(0xFF0284C7), Color(0xFF0369A1)], begin: Alignment.topLeft, end: Alignment.bottomRight)
                : null,
            color: isSelected ? null : (isLight ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B)),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected ? const Color(0xFF38BDF8) : (isLight ? const Color(0xFFCBD5E1) : const Color(0xFF334155)),
              width: isSelected ? 1.5 : 1.0,
            ),
            boxShadow: isSelected ? [BoxShadow(color: const Color(0xFF0284C7).withValues(alpha: 0.35), blurRadius: 6, offset: const Offset(0, 2))] : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: isSelected ? Colors.white : const Color(0xFF0284C7)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 12.0,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.white : (isLight ? const Color(0xFF0F172A) : Colors.white),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isSelected) const Icon(Icons.check_circle, size: 14, color: Colors.white),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w500,
                  color: isSelected ? Colors.white.withValues(alpha: 0.85) : (isLight ? const Color(0xFF64748B) : Colors.white60),
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
    final coverIncluded = widget.instance != null
        ? (_localCoverIncluded ?? widget.instance!.coverConfiguration.included)
        : (widget.viewModel?.hasCover ?? (widget.viewModel?.document.cover != null));

    void toggleCoverState(bool newIncluded) {
      setState(() {
        _localCoverIncluded = newIncluded;
      });
      if (widget.instance != null && widget.onInstanceChanged != null) {
        final updated = widget.instance!.copyWith(coverConfiguration: widget.instance!.coverConfiguration.copyWith(included: newIncluded));
        widget.onInstanceChanged!(updated);
      } else if (widget.viewModel != null) {
        if (_isLadder) {
          widget.viewModel!.applyCmsMorphParameter('include_cover', newIncluded ? 1.0 : 0.0);
        } else {
          if (newIncluded) {
            widget.viewModel!.createCoverForCurrentFitting();
          } else {
            widget.viewModel!.removeCover();
          }
        }
      }
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isLight ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: coverIncluded ? const Color(0xFF0284C7).withValues(alpha: 0.5) : (isLight ? const Color(0xFFE2E8F0) : const Color(0xFF334155)),
          width: 1.0,
        ),
      ),
      child: Column(
        children: [
          // Clickable Toggle Button Row for Parametric Cover
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(5),
              onTap: () => toggleCoverState(!coverIncluded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          coverIncluded ? Icons.shield : Icons.shield_outlined,
                          size: 16,
                          color: coverIncluded ? const Color(0xFF0284C7) : (isLight ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Parametric Cover',
                          style: TextStyle(fontSize: 12.0, fontWeight: FontWeight.bold, color: isLight ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        if (coverIncluded) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.5), width: 0.8),
                            ),
                            child: Text(
                              widget.instance?.coverConfiguration.placementMode3D.toUpperCase() ?? 'EXPLODED',
                              style: const TextStyle(fontSize: 9.0, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                            ),
                          ),
                        ],
                        // Interactive Capsule Toggle Button
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: coverIncluded ? const Color(0xFF0284C7) : (isLight ? const Color(0xFFE2E8F0) : const Color(0xFF334155)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            coverIncluded ? 'ON' : 'OFF',
                            style: TextStyle(
                              fontSize: 10.0,
                              fontWeight: FontWeight.bold,
                              color: coverIncluded ? Colors.white : (isLight ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
                            ),
                          ),
                        ),
                      ],
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
                  child: _buildStepperField('Cover Flange', 'cover_flange_size', 6.0, 45.0, step: 1.0, decimals: 0, presetSizes: const [10, 12, 15, 20, 25]),
                ),
              ],
            ),
            const SizedBox(height: 5),
            // Quick preset chips for cover flange
            Row(
              children: [
                Text(
                  'Presets:',
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: isLight ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
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
                child: _buildStepperField('Thickness', 'thickness', 0.6, 5.0, step: 0.1, decimals: 2, presetSizes: const [0.8, 1.0, 1.2, 1.5, 2.0, 2.5, 3.0]),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 5,
                child: PopupMenuButton<String>(
                  tooltip: 'Select Material',
                  initialValue: _currentMaterial,
                  onSelected: (val) {
                    _updateMaterial(val);
                  },
                  itemBuilder: (ctx) => [
                    for (final mat in _availableMaterials)
                      PopupMenuItem(
                        value: mat.name,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: mat.isStainless
                                    ? Colors.amber.withValues(alpha: 0.15)
                                    : (mat.isAluminium
                                        ? Colors.purple.withValues(alpha: 0.15)
                                        : (mat.isPlastic
                                            ? Colors.teal.withValues(alpha: 0.15)
                                            : Colors.blue.withValues(alpha: 0.15))),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                mat.shortCode,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: mat.isStainless
                                      ? Colors.amber[800]
                                      : (mat.isAluminium
                                          ? Colors.purple[700]
                                          : (mat.isPlastic
                                              ? Colors.teal[700]
                                              : const Color(0xFF0284C7))),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(mat.name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      ),
                  ],
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
                            _currentMaterial,
                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: isLight ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down, size: 16, color: Color(0xFF94A3B8)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          // Quick gauge chips (wrap to prevent pixel overflow)
          Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Gauge:',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: isLight ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
              ),
              for (final th in [0.8, 1.0, 1.2, 1.5, 2.0, 2.5, 3.0]) ...[
                InkWell(
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
                        color: (curThick - th).abs() < 0.05 ? const Color(0xFF0284C7) : (isLight ? const Color(0xFFCBD5E1) : const Color(0xFF475569)),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      '${th.toStringAsFixed(2)} mm',
                      style: TextStyle(
                        fontSize: 10.0,
                        fontWeight: (curThick - th).abs() < 0.05 ? FontWeight.bold : FontWeight.w500,
                        color: (curThick - th).abs() < 0.05 ? const Color(0xFF0284C7) : (isLight ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          // 3D Shader Material Preset link row
          Builder(builder: (ctx) {
            final activeSettings = widget.viewModel?.graphicsPreferences.materialSettings ??
                CadMaterialSettings.preset(CadMaterialSettings.presetFromMaterialGrade(_currentMaterial));
            final preset = activeSettings.preset;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
              decoration: BoxDecoration(
                color: isLight ? Colors.white : const Color(0xFF1E293B).withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isLight ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
                  width: 0.8,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: activeSettings.baseColor,
                      border: Border.all(
                        color: isLight ? const Color(0xFFCBD5E1) : const Color(0xFF64748B),
                        width: 1.0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '3D Shader:',
                    style: TextStyle(
                      fontSize: 10.0,
                      fontWeight: FontWeight.w700,
                      color: isLight ? const Color(0xFF475569) : const Color(0xFF94A3B8),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      preset.label,
                      style: TextStyle(
                        fontSize: 10.0,
                        fontWeight: FontWeight.w600,
                        color: isLight ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (activeSettings.useSpangles) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: Colors.amber[700]!, width: 0.5),
                      ),
                      child: Text(
                        'SPANGLE',
                        style: TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                          color: isLight ? Colors.amber[900] : Colors.amber[300],
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ] else if (activeSettings.isPlastic) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: Colors.teal.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: Colors.teal[600]!, width: 0.5),
                      ),
                      child: Text(
                        'DIELECTRIC',
                        style: TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                          color: isLight ? Colors.teal[900] : Colors.teal[300],
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  PopupMenuButton<CadMaterialPresetType>(
                    tooltip: 'Change 3D Shader Preset',
                    onSelected: (val) => _updateShaderPreset(val),
                    itemBuilder: (ctx) => [
                      for (final p in CadMaterialPresetType.values)
                        PopupMenuItem(
                          value: p,
                          height: 28,
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: CadMaterialSettings.preset(p).baseColor,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                p.label,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: p == preset ? FontWeight.bold : FontWeight.w500,
                                  color: const Color(0xFF1E293B),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: isLight ? const Color(0xFFF1F5F9) : const Color(0xFF334155),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Icon(
                        Icons.tune,
                        size: 13,
                        color: isLight ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
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
                  color: isMatch ? const Color(0xFF0284C7).withValues(alpha: 0.2) : (isLight ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B)),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isMatch ? const Color(0xFF0284C7) : (isLight ? const Color(0xFFCBD5E1) : const Color(0xFF475569)),
                    width: isMatch ? 1.2 : 0.8,
                  ),
                ),
                child: Text(
                  ps,
                  style: TextStyle(
                    fontSize: 11.0,
                    fontWeight: isMatch ? FontWeight.bold : FontWeight.w600,
                    color: isMatch ? const Color(0xFF0284C7) : (isLight ? const Color(0xFF1E293B) : Colors.white),
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
    final currentMat = _currentMaterial;
    final density = DdsInstanceEvaluator.resolveDensity(currentMat);
    final thickness =
        ((_currentParams["thickness"] ?? widget.instance?.instanceParameters['thickness'] ?? widget.viewModel?.document.material.thicknessMm ?? 1.5) as num)
            .toDouble();

    // 1. Determine surface area (m²)
    double blankAreaM2 = 0.0;
    if (takeoff != null && takeoff.blankSurfaceAreaM2 > 0) {
      blankAreaM2 = takeoff.blankSurfaceAreaM2;
    } else if (widget.viewModel != null) {
      final doc = widget.viewModel!.document;
      double totalAreaMm2 = 0;
      if (doc.faces.isNotEmpty) {
        for (final face in doc.faces) {
          totalAreaMm2 += face.areaMm2.abs();
        }
      }
      if (totalAreaMm2 <= 0 && doc.outerContour.length >= 3) {
        for (int i = 0; i < doc.outerContour.length; i++) {
          final j = (i + 1) % doc.outerContour.length;
          totalAreaMm2 += doc.outerContour[i].x * doc.outerContour[j].y - doc.outerContour[j].x * doc.outerContour[i].y;
        }
        totalAreaMm2 = (totalAreaMm2 / 2.0).abs();
      }
      if (totalAreaMm2 <= 0) {
        totalAreaMm2 = doc.blankAreaMm2;
      }
      if (totalAreaMm2 > 0) {
        blankAreaM2 = totalAreaMm2 / 1000000.0;
      }
    }

    if (blankAreaM2 <= 0) {
      blankAreaM2 = 0.185;
    }

    // 2. ALWAYS calculate live net weight dynamically from active area, active thickness, and active material density!
    final netWeightKg = blankAreaM2 * (thickness / 1000.0) * density;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0F1D),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF1E293B), width: 1.0),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildTakeoffItem('BLANK AREA', '${blankAreaM2.toStringAsFixed(3)} m²'),
          Container(width: 1, height: 26, color: const Color(0xFF1E293B)),
          _buildTakeoffItem('NET WEIGHT', '${netWeightKg.toStringAsFixed(2)} kg'),
          Container(width: 1, height: 26, color: const Color(0xFF1E293B)),
          _buildTakeoffItem('GAUGE', '${thickness.toStringAsFixed(2)} mm'),
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
          style: const TextStyle(fontSize: 9.5, color: Color(0xFF94A3B8), fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontSize: 13.0, color: Color(0xFF00E5FF), fontWeight: FontWeight.bold, fontFamily: 'monospace'),
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
        final align = widget.viewModel?.scalingController?.reducerAlignment ?? ReducerAlignment.straight;
        switch (align) {
          case ReducerAlignment.left:
            return 'Left Reducer (Inlet & Outlet)';
          case ReducerAlignment.right:
            return 'Right Reducer (Inlet & Outlet)';
          case ReducerAlignment.straight:
            return 'Straight Reducer (Inlet & Outlet)';
        }
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

class _MaterialOption {
  final String shortCode;
  final String name;
  final bool isStainless;
  final bool isAluminium;
  final bool isPlastic;
  const _MaterialOption(this.shortCode, this.name, {this.isStainless = false, this.isAluminium = false, this.isPlastic = false});
}
