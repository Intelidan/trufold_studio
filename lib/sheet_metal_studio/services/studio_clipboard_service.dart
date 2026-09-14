// =============================================================================
// studio_clipboard_service.dart
//
// Inter-File & Multi-Tab Clipboard Service for Danish FormMatrix Studio.
// Allows copying and pasting CAD features between open files:
// - CNC Punches (Round, Obround, Rectangle)
// - Perforation Array Patterns
// - Press-Brake Fold Bend Lines
// - Laser Cut Lines / Slits
// Supports both in-memory cross-tab exchange and system OS clipboard sync.
// =============================================================================

import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/cnc_punch_primitive.dart';
import '../models/perforation_pattern.dart';
import '../models/fold_bend_line.dart';
import '../models/cad_primitives.dart';
import '../viewmodels/sheet_metal_studio_viewmodel.dart';

enum ClipboardContentType {
  punch,
  pattern,
  bend,
  cut,
  multiple,
}

class StudioClipboardItem {
  final ClipboardContentType type;
  final Map<String, dynamic> data;
  final String label;

  const StudioClipboardItem({
    required this.type,
    required this.data,
    required this.label,
  });

  Map<String, dynamic> toJson() => {
    'magic': 'DANISH_STUDIO_CLIPBOARD',
    'version': '1.0',
    'type': type.name,
    'label': label,
    'data': data,
  };

  static StudioClipboardItem? fromJson(Map<String, dynamic> json) {
    if (json['magic'] != 'DANISH_STUDIO_CLIPBOARD') return null;
    final typeName = json['type'] as String?;
    final type = ClipboardContentType.values.firstWhere(
      (e) => e.name == typeName,
      orElse: () => ClipboardContentType.punch,
    );
    final data = json['data'] as Map<String, dynamic>? ?? {};
    final label = json['label'] as String? ?? 'CAD Feature';
    return StudioClipboardItem(type: type, data: data, label: label);
  }
}

class StudioClipboardService {
  static StudioClipboardItem? _inMemoryItem;

  /// Returns true if there is an item in memory or available on the clipboard
  static bool get hasContent => _inMemoryItem != null;

  /// Label of current item in clipboard
  static String get currentLabel => _inMemoryItem?.label ?? 'Empty';

  /// Copies currently selected entity from the given ViewModel into clipboard
  static Future<bool> copySelection(SheetMetalStudioViewModel vm) async {
    final doc = vm.document;

    // 1. Check selected punch
    if (vm.selectedPunchId != null) {
      final punch = doc.punches.cast<CncPunchPrimitive?>().firstWhere(
        (p) => p?.id == vm.selectedPunchId,
        orElse: () => null,
      );
      if (punch != null) {
        final item = StudioClipboardItem(
          type: ClipboardContentType.punch,
          data: punch.toJson(),
          label: 'Punch (${punch.type.name.toUpperCase()} ${punch.id})',
        );
        return _storeClipboard(item);
      }
    }

    // 2. Check selected perforation pattern
    if (vm.selectedPatternId != null) {
      final pattern = doc.perforationPatterns.cast<PerforationPattern?>().firstWhere(
        (p) => p?.id == vm.selectedPatternId,
        orElse: () => null,
      );
      if (pattern != null) {
        final item = StudioClipboardItem(
          type: ClipboardContentType.pattern,
          data: pattern.toJson(),
          label: 'Perforation Pattern (${pattern.id} ${pattern.countX}x${pattern.countY})',
        );
        return _storeClipboard(item);
      }
    }

    // 3. Check selected bend line
    if (vm.selectedBendId != null) {
      final bend = doc.bends.cast<FoldBendLine?>().firstWhere(
        (b) => b?.id == vm.selectedBendId,
        orElse: () => null,
      );
      if (bend != null) {
        final item = StudioClipboardItem(
          type: ClipboardContentType.bend,
          data: bend.toJson(),
          label: 'Bend Line (${bend.id} ${bend.direction.name.toUpperCase()} ${bend.targetAngleDeg.toStringAsFixed(0)}°)',
        );
        return _storeClipboard(item);
      }
    }

    // 4. Check selected cut line
    if (vm.selectedCutId != null) {
      final cut = doc.cutLines.cast<CadLineSegment?>().firstWhere(
        (c) => c?.id == vm.selectedCutId,
        orElse: () => null,
      );
      if (cut != null) {
        final item = StudioClipboardItem(
          type: ClipboardContentType.cut,
          data: cut.toJson(),
          label: 'Cut Slit (${cut.id})',
        );
        return _storeClipboard(item);
      }
    }

    return false;
  }

  static Future<bool> _storeClipboard(StudioClipboardItem item) async {
    _inMemoryItem = item;
    try {
      final jsonStr = jsonEncode(item.toJson());
      await Clipboard.setData(ClipboardData(text: jsonStr));
    } catch (_) {}
    return true;
  }

  /// Pastes clipboard content into the target ViewModel
  static Future<String?> pasteInto(SheetMetalStudioViewModel vm, {double offsetX = 15.0, double offsetY = 15.0}) async {
    // 1. Check system clipboard if memory is empty
    StudioClipboardItem? item = _inMemoryItem;
    if (item == null) {
      try {
        final sysData = await Clipboard.getData(Clipboard.kTextPlain);
        if (sysData?.text != null && sysData!.text!.isNotEmpty) {
          final decoded = jsonDecode(sysData.text!);
          if (decoded is Map<String, dynamic>) {
            item = StudioClipboardItem.fromJson(decoded);
          }
        }
      } catch (_) {}
    }

    if (item == null) return null;

    final doc = vm.document;
    final timestamp = DateTime.now().millisecondsSinceEpoch % 10000;

    switch (item.type) {
      case ClipboardContentType.punch:
        final original = CncPunchPrimitive.fromJson(item.data);
        final newId = 'PUNCH_CPY_$timestamp';
        final newPunch = original.copyWith(
          id: newId,
          center: CadPoint2D(original.center.x + offsetX, original.center.y + offsetY),
        );
        final newPunches = [...doc.punches, newPunch];
        vm.updateDocument(doc.copyWith(punches: newPunches));
        vm.selectPunch(newId);
        return 'Pasted ${item.label} as $newId';

      case ClipboardContentType.pattern:
        final original = PerforationPattern.fromJson(item.data);
        final newId = 'PAT_CPY_$timestamp';
        final newPattern = original.copyWith(
          id: newId,
          anchor: CadPoint2D(original.anchor.x + offsetX, original.anchor.y + offsetY),
        );
        final newPatterns = [...doc.perforationPatterns, newPattern];
        vm.updateDocument(doc.copyWith(perforationPatterns: newPatterns));
        vm.selectPattern(newId);
        return 'Pasted ${item.label} as $newId';

      case ClipboardContentType.bend:
        final original = FoldBendLine.fromJson(item.data);
        final newId = 'B_CPY_$timestamp';
        final newBend = original.copyWith(
          id: newId,
          p1: CadPoint2D(original.p1.x + offsetX, original.p1.y + offsetY),
          p2: CadPoint2D(original.p2.x + offsetX, original.p2.y + offsetY),
        );
        final newBends = [...doc.bends, newBend];
        vm.updateDocument(doc.copyWith(bends: newBends));
        vm.selectBend(newId);
        return 'Pasted ${item.label} as $newId';

      case ClipboardContentType.cut:
        final original = CadLineSegment.fromJson(item.data);
        final newId = 'CUT_CPY_$timestamp';
        final newCut = CadLineSegment(
          id: newId,
          p1: CadPoint2D(original.p1.x + offsetX, original.p1.y + offsetY),
          p2: CadPoint2D(original.p2.x + offsetX, original.p2.y + offsetY),
          layer: original.layer,
        );
        final newCuts = [...doc.cutLines, newCut];
        vm.updateDocument(doc.copyWith(cutLines: newCuts));
        vm.selectCut(newId);
        return 'Pasted ${item.label} as $newId';

      case ClipboardContentType.multiple:
        return null;
    }
  }
}
