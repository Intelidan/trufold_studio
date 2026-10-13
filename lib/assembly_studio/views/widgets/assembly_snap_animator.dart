import 'package:flutter/material.dart';

import '../../../sheet_metal_studio/models/cad_primitives.dart';
import '../../models/assembly_part.dart';
import '../../models/assembly_docking_zone.dart';

/// Coordinates smooth animated magnetic snap glides, 3D target color-shifting,
/// and anchor-centered scale pulsing for the Assembly Studio 3D Viewport.
class AssemblySnapAnimator {
  final TickerProvider vsync;
  final Duration snapDuration;

  late final AnimationController _controller;
  SnapAnimationState? _activeAnimation;
  VoidCallback? _onCompleteCallback;

  // Visual Highlight & Scale Pulse State
  String? _highlightedPartId;
  double _targetScaleFactor = 1.0;
  Color? _highlightTintColor;
  bool _isSnapping = false;

  void Function(CadPoint3D interpolatedPos)? _onTickCallback;

  AssemblySnapAnimator({
    required this.vsync,
    this.snapDuration = const Duration(milliseconds: 240),
  }) {
    _controller = AnimationController(
      vsync: vsync,
      duration: snapDuration,
    );
    _controller.addListener(_handleAnimationTick);
  }

  void _handleAnimationTick() {
    if (_activeAnimation == null) return;
    final curvedT = Curves.easeOutCubic.transform(_controller.value);
    _activeAnimation = SnapAnimationState(
      sourcePart: _activeAnimation!.sourcePart,
      startPosition: _activeAnimation!.startPosition,
      targetPosition: _activeAnimation!.targetPosition,
      sourceSnap: _activeAnimation!.sourceSnap,
      targetSnap: _activeAnimation!.targetSnap,
      progress: curvedT,
      isComplete: _controller.isCompleted,
    );

    _onTickCallback?.call(_activeAnimation!.currentPosition);
  }

  /// Whether an animated snap transition is currently in progress.
  bool get isSnapping => _isSnapping;

  /// The active animation state (if any).
  SnapAnimationState? get activeAnimation => _activeAnimation;

  /// ID of the part currently highlighted as a drop or snap target.
  String? get highlightedPartId => _highlightedPartId;

  /// Current scale multiplier for the highlighted target part (defaults to 1.0).
  double get targetScaleFactor => _targetScaleFactor;

  /// Color tint for the highlighted target part.
  Color? get highlightTintColor => _highlightTintColor;

  /// Sets the visual highlight and anchor-centered scale pulse for a target entity.
  void setTargetHighlight({
    required String? partId,
    bool isSnapped = false,
    Color? customColor,
  }) {
    if (partId == null) {
      _highlightedPartId = null;
      _targetScaleFactor = 1.0;
      _highlightTintColor = null;
    } else {
      _highlightedPartId = partId;
      _targetScaleFactor = isSnapped ? 1.04 : 1.02; // Subtle 2-4% scale pulse
      _highlightTintColor = customColor ?? (isSnapped ? const Color(0xFF10B981) : const Color(0xFF00E5FF));
    }
  }

  /// Initiates a smooth, ease-out cubic magnetic snap glide from [startPos] to [targetPos].
  ///
  /// Disables external drag inputs while running (`isSnapping = true`),
  /// updates positions smoothly each frame, and calls [onComplete] upon settling.
  void startSnapGlide({
    required AssemblyPart sourcePart,
    required CadPoint3D startPos,
    required CadPoint3D targetPos,
    required AssemblySnapPoint sourceSnap,
    required AssemblySnapPoint targetSnap,
    required void Function(CadPoint3D interpolatedPos) onTick,
    required VoidCallback onComplete,
  }) {
    if (_isSnapping) {
      _controller.stop();
    }

    _isSnapping = true;
    _onCompleteCallback = onComplete;
    _onTickCallback = onTick;

    _activeAnimation = SnapAnimationState(
      sourcePart: sourcePart,
      startPosition: startPos,
      targetPosition: targetPos,
      sourceSnap: sourceSnap,
      targetSnap: targetSnap,
      progress: 0.0,
    );

    // Lock target highlight during the glide
    setTargetHighlight(partId: targetSnap.partId, isSnapped: true);

    _controller.forward(from: 0.0).then((_) {
      _isSnapping = false;
      _activeAnimation = null;
      _onTickCallback = null;

      // Clean teardown: reset target highlight & scale pulse
      setTargetHighlight(partId: null);

      _onCompleteCallback?.call();
      _onCompleteCallback = null;
    });
  }

  /// Disposes the animation controller.
  void dispose() {
    _controller.removeListener(_handleAnimationTick);
    _controller.dispose();
  }
}
