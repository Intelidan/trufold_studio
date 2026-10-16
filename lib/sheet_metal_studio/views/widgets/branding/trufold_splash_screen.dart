// =============================================================================
// trufold_splash_screen.dart
//
// Interactive Startup Splash Screen and 3D Studio Launcher for truFold Studio.
// Verifies Flutter GPU (flutter_scene / Impeller) hardware acceleration availability.
// Features tactile 3D animated launch cards for CAD Studio, Assembly Studio,
// and TDS Studio (Technical Data Sheet Suite).
// =============================================================================

import 'dart:io' show exit;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../engine/trufold_3d_engine_preloader.dart';
import 'trufold_3d_icon.dart';

/// Supported studio workspace targets selectable from the 3D launch screen.
enum StudioLaunchTarget {
  cad,
  assembly,
  tds,
}

/// Full-featured animated splash screen and 3D studio launcher for truFold Studio.
class TruFoldSplashScreen extends StatefulWidget {
  /// Callback triggered when a specific studio workspace is selected.
  final void Function(StudioLaunchTarget target)? onLaunchStudio;

  /// Optional fallback callback triggered if legacy single-target launch is used.
  final VoidCallback? onInitializationComplete;

  /// Duration before completing the initial brand reveal animation.
  final Duration totalDuration;

  /// Whether to allow the user to skip the opening animation to see the 3D launcher immediately.
  final bool allowTapToSkip;

  const TruFoldSplashScreen({
    super.key,
    this.onLaunchStudio,
    this.onInitializationComplete,
    this.totalDuration = const Duration(milliseconds: 2800),
    this.allowTapToSkip = true,
  });

  @override
  State<TruFoldSplashScreen> createState() => _TruFoldSplashScreenState();
}

class _TruFoldSplashScreenState extends State<TruFoldSplashScreen> with TickerProviderStateMixin {
  late AnimationController _mainController;
  late Animation<double> _laserTraceAnim;
  late Animation<double> _foldProgressAnim;
  late Animation<double> _textFadeAnim;
  late Animation<Offset> _textSlideAnim;
  late Animation<double> _statusFadeAnim;
  late Animation<double> _cardsFadeAnim;
  late Animation<Offset> _cardsSlideAnim;

  String _activeStatusMessage = 'Verifying Impeller GPU backend...';
  bool _isGpuChecking = true;
  bool _isGpuAvailable = true;
  bool _isRetryingGpu = false;
  bool _hasTriggeredCompletion = false;
  Object? _gpuError;

  StudioLaunchTarget _focusedTarget = StudioLaunchTarget.cad;

  @override
  void initState() {
    super.initState();

    _mainController = AnimationController(vsync: this, duration: widget.totalDuration);

    // 1. Laser cut outline trace: 0% -> 28%
    _laserTraceAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.28, curve: Curves.easeInOut),
      ),
    );

    // 2. 3D Folding of the 'F' flap (0° -> 75°): 18% -> 65%
    _foldProgressAnim = Tween<double>(begin: 0.0, end: 75.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.18, 0.65, curve: Curves.easeOutBack),
      ),
    );

    // 3. Logo Typography Fade & Slide: 25% -> 65%
    _textFadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.25, 0.65, curve: Curves.easeOut),
      ),
    );
    _textSlideAnim = Tween<Offset>(begin: const Offset(0.0, 0.15), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.25, 0.65, curve: Curves.easeOutCubic),
      ),
    );

    // 4. Status Bar & Loading: 20% -> 50%
    _statusFadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.20, 0.50, curve: Curves.easeIn),
      ),
    );

    // 5. 3D Studio Cards Entrance: Fade and spring slide up: 30% -> 75%
    _cardsFadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.30, 0.75, curve: Curves.easeOut),
      ),
    );
    _cardsSlideAnim = Tween<Offset>(begin: const Offset(0.0, 0.12), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.30, 0.75, curve: Curves.easeOutCubic),
      ),
    );

    _startEnginePreload();

    _mainController.forward();
    _mainController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (widget.onLaunchStudio == null) {
          _completeInitialization();
        }
      }
    });
  }

  void _startEnginePreload() {
    TruFold3dEnginePreloader.instance.preload(
      onProgress: (status, _) {
        if (!mounted) return;
        setState(() {
          _activeStatusMessage = status;
        });
      },
    ).then((_) {
      if (!mounted) return;
      setState(() {
        _isGpuChecking = false;
        _isGpuAvailable = TruFold3dEnginePreloader.instance.isGpuAvailable;
        _gpuError = TruFold3dEnginePreloader.instance.lastError;
      });
      if (_mainController.isCompleted && widget.onLaunchStudio == null) {
        _completeInitialization();
      }
    }).catchError((err) {
      if (!mounted) return;
      setState(() {
        _isGpuChecking = false;
        _isGpuAvailable = false;
        _gpuError = err;
      });
      if (_mainController.isCompleted && widget.onLaunchStudio == null) {
        _completeInitialization();
      }
    });
  }

  void _completeInitialization() {
    if (_hasTriggeredCompletion) return;
    _hasTriggeredCompletion = true;
    widget.onInitializationComplete?.call();
  }

  void _retryImpellerVerification() async {
    setState(() {
      _isRetryingGpu = true;
      _isGpuChecking = true;
      _activeStatusMessage = 'Retrying Impeller GPU verification...';
    });

    await TruFold3dEnginePreloader.instance.retryPreload(
      onProgress: (status, _) {
        if (!mounted) return;
        setState(() {
          _activeStatusMessage = status;
        });
      },
    );

    if (!mounted) return;
    setState(() {
      _isRetryingGpu = false;
      _isGpuChecking = false;
      _isGpuAvailable = TruFold3dEnginePreloader.instance.isGpuAvailable;
      _gpuError = TruFold3dEnginePreloader.instance.lastError;
    });
  }

  void _launchStudio(StudioLaunchTarget target) {
    if (!_isGpuChecking && !_isGpuAvailable) return;
    if (widget.onLaunchStudio != null) {
      widget.onLaunchStudio!(target);
    } else {
      _completeInitialization();
    }
  }

  void _skip() {
    if (widget.allowTapToSkip) {
      if (widget.onLaunchStudio == null) {
        _mainController.stop();
        _completeInitialization();
      } else {
        _mainController.animateTo(1.0, duration: const Duration(milliseconds: 150));
      }
    }
  }

  @override
  void dispose() {
    _mainController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.digit1): () => _launchStudio(StudioLaunchTarget.cad),
        const SingleActivator(LogicalKeyboardKey.numpad1): () => _launchStudio(StudioLaunchTarget.cad),
        const SingleActivator(LogicalKeyboardKey.digit2): () => _launchStudio(StudioLaunchTarget.assembly),
        const SingleActivator(LogicalKeyboardKey.numpad2): () => _launchStudio(StudioLaunchTarget.assembly),
        const SingleActivator(LogicalKeyboardKey.digit3): () => _launchStudio(StudioLaunchTarget.tds),
        const SingleActivator(LogicalKeyboardKey.numpad3): () => _launchStudio(StudioLaunchTarget.tds),
        const SingleActivator(LogicalKeyboardKey.enter): () => _launchStudio(_focusedTarget),
        const SingleActivator(LogicalKeyboardKey.numpadEnter): () => _launchStudio(_focusedTarget),
      },
      child: Focus(
        autofocus: true,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _skip,
          child: Scaffold(
            backgroundColor: const Color(0xFF070B14), // Deep Obsidian CAD Canvas
            body: Stack(
              children: [
                // 1. Animated Blueprint CAD Grid Background
                Positioned.fill(child: CustomPaint(painter: _BlueprintGridBackgroundPainter())),

                // 2. Ambient High-Tech Volumetric Backlight Glows
                Positioned.fill(
                  child: Center(
                    child: Container(
                      width: 750,
                      height: 600,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            const Color(0xFF0284C7).withValues(alpha: 0.14),
                            const Color(0xFF0F172A).withValues(alpha: 0.04),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.55, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),

                // 3. Central Interactive Layout
                SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                      child: AnimatedBuilder(
                        animation: _mainController,
                        builder: (context, _) {
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // --- Brand Header (3D Icon + truFold by danish STUDIO) ---
                              _buildBrandHeader(),
                              const SizedBox(height: 24),

                              // --- Content Area: Either Impeller Warning, Launcher Cards, or Loading Bar ---
                              if (!_isGpuChecking && !_isGpuAvailable)
                                _buildImpellerRequiredCard()
                              else
                                FadeTransition(
                                  opacity: _cardsFadeAnim,
                                  child: SlideTransition(
                                    position: _cardsSlideAnim,
                                    child: _buildStudioSelectionSuite(),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),

                // 4. Bottom System Status Bar
                _buildBottomStatusBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Builds the 3D folding icon and truFold brand typography with "by danish" credit.
  Widget _buildBrandHeader() {
    const iconSize = 96.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 3D Folding Icon with Laser Perimeter Ring
        SizedBox(
          width: iconSize + 16,
          height: iconSize + 16,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (_laserTraceAnim.value < 1.0)
                CustomPaint(
                  size: const Size(iconSize + 16, iconSize + 16),
                  painter: _LaserCutTracePainter(progress: _laserTraceAnim.value),
                ),
              TruFold3DIcon(
                size: iconSize,
                isAnimated: false,
                fixedFoldAngleDeg: _foldProgressAnim.value,
                showGrid: false,
                showAnnotations: false,
                sheetThickness: 2.8,
                tColor: const Color(0xFF38BDF8),
                fColor: const Color(0xFF94A3B8),
                accentColor: const Color(0xFFF97316),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Logo Typography
        FadeTransition(
          opacity: _textFadeAnim,
          child: SlideTransition(
            position: _textSlideAnim,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    const Text(
                      'truFold',
                      style: TextStyle(
                        color: Color(0xFFF8FAFC),
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.0,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: const Color(0xFF38BDF8).withValues(alpha: 0.6),
                          width: 1.0,
                        ),
                      ),
                      child: const Text(
                        'STUDIO',
                        style: TextStyle(
                          color: Color(0xFF38BDF8),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'by danish',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 2.0,
                        fontFamily: 'monospace',
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(
                        color: Color(0xFF475569),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const Text(
                      'ENTERPRISE SHEET METAL CAD & ASSEMBLY SUITE',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.6,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Responsive bottom system status bar with live Impeller GPU accelerator indicator.
  Widget _buildBottomStatusBar() {
    return Positioned(
      bottom: 12,
      left: 20,
      right: 20,
      child: FadeTransition(
        opacity: _statusFadeAnim,
        child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              'truFold Studio v3.2.0 • Danish Innovations',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF475569),
                fontSize: 9.5,
                fontFamily: 'monospace',
                letterSpacing: 0.4,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isGpuChecking
                      ? const Color(0xFF38BDF8)
                      : (_isGpuAvailable ? const Color(0xFF10B981) : const Color(0xFFEF4444)),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _isGpuChecking
                    ? _activeStatusMessage
                    : (_isGpuAvailable
                        ? 'Impeller GPU Hardware Accelerated (120 FPS)'
                        : 'Impeller Backend Required'),
                style: TextStyle(
                  color: _isGpuChecking
                      ? const Color(0xFF38BDF8)
                      : (_isGpuAvailable ? const Color(0xFF10B981) : const Color(0xFFF87171)),
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

  /// High-Tech 3D Diagnostics Card displayed when Impeller is not enabled on startup.
  Widget _buildImpellerRequiredCard() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 620),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEF4444).withValues(alpha: 0.18),
            blurRadius: 36,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFEF4444), width: 1.2),
                ),
                child: const Icon(Icons.warning_amber_rounded, size: 28, color: Color(0xFFEF4444)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Impeller GPU Backend Required',
                      style: TextStyle(
                        color: Color(0xFFF8FAFC),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.2,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Legacy 2D software painter engine has been retired. TruFold Studio requires Flutter GPU (Impeller) for 120 FPS hardware-accelerated 3D rendering.',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5, height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Diagnostic instruction box
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF030712),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF334155), width: 0.8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.terminal_rounded, size: 14, color: Color(0xFF38BDF8)),
                    const SizedBox(width: 6),
                    const Text(
                      'Run TruFold Studio with Impeller on Windows:',
                      style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 10.5, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SelectableText(
                  'flutter run -d windows --enable-impeller',
                  style: const TextStyle(
                    color: Color(0xFF34D399),
                    fontSize: 12,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_gpuError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Diagnostic trace: $_gpuError',
                    style: const TextStyle(color: Color(0xFFF87171), fontSize: 9.5, fontFamily: 'monospace'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Action buttons: Retry and Exit
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: () => exit(0),
                icon: const Icon(Icons.close_rounded, size: 14),
                label: const Text('Exit App'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF94A3B8),
                  side: const BorderSide(color: Color(0xFF475569)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _isRetryingGpu ? null : _retryImpellerVerification,
                icon: _isRetryingGpu
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.refresh_rounded, size: 16),
                label: Text(_isRetryingGpu ? 'Verifying...' : 'Retry Impeller Detection'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                  elevation: 6,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Renders the 3 Intuitive Animated 3D Studio Cards for CAD, Assembly, and TDS.
  Widget _buildStudioSelectionSuite() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Section header badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B).withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.widgets_outlined, size: 12, color: Color(0xFF38BDF8)),
              SizedBox(width: 6),
              Text(
                'SELECT WORKSPACE TO LAUNCH',
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // 3 Tactile 3D Cards
        Wrap(
          spacing: 18,
          runSpacing: 18,
          alignment: WrapAlignment.center,
          children: [
            // Card 1: CAD Studio
            _StudioLaunchCard(
              title: 'CAD Studio',
              subtitle: 'Sheet Metal Modeling & Unfolding',
              badge: '120 FPS GPU',
              description: 'Parametric 2D/3D flange modeling, automatic bend unwrapping, flat pattern export & laser nesting.',
              shortcutKey: '1',
              accentColor: const Color(0xFF0284C7),
              glowColor: const Color(0xFF38BDF8),
              icon: Icons.architecture_rounded,
              isFocused: _focusedTarget == StudioLaunchTarget.cad,
              onTap: () => _launchStudio(StudioLaunchTarget.cad),
              onHover: (hovered) {
                if (hovered) setState(() => _focusedTarget = StudioLaunchTarget.cad);
              },
            ),

            // Card 2: Assembly Studio
            _StudioLaunchCard(
              title: 'Assembly Studio',
              subtitle: 'Multi-Part Mating & Welding',
              badge: 'MULTI-BODY',
              description: 'Zero-jump 60 FPS part manipulation, Onshape mate connectors, real-time welding simulation & audit.',
              shortcutKey: '2',
              accentColor: const Color(0xFF059669),
              glowColor: const Color(0xFF34D399),
              icon: Icons.precision_manufacturing_rounded,
              isFocused: _focusedTarget == StudioLaunchTarget.assembly,
              onTap: () => _launchStudio(StudioLaunchTarget.assembly),
              onHover: (hovered) {
                if (hovered) setState(() => _focusedTarget = StudioLaunchTarget.assembly);
              },
            ),

            // Card 3: TDS Studio
            _StudioLaunchCard(
              title: 'TDS Studio',
              subtitle: 'Technical Data Sheet & Submittal',
              badge: 'ISO 7200',
              description: 'ISO 7200 drawing canvas, Excel order parsing, CMS template synchronization & client submittals.',
              shortcutKey: '3',
              accentColor: const Color(0xFF7C3AED),
              glowColor: const Color(0xFFA78BFA),
              icon: Icons.description_rounded,
              isFocused: _focusedTarget == StudioLaunchTarget.tds,
              onTap: () => _launchStudio(StudioLaunchTarget.tds),
              onHover: (hovered) {
                if (hovered) setState(() => _focusedTarget = StudioLaunchTarget.tds);
              },
            ),
          ],
        ),
      ],
    );
  }
}

/// Tactile, Intuitive 3D Launch Card for Studio Selection.
/// Implements 3D layered drop shadows, chamfer highlight borders, elevation on hover,
/// and tactile mechanical depression on press.
class _StudioLaunchCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final String badge;
  final String description;
  final String shortcutKey;
  final Color accentColor;
  final Color glowColor;
  final IconData icon;
  final bool isFocused;
  final VoidCallback onTap;
  final ValueChanged<bool>? onHover;

  const _StudioLaunchCard({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.description,
    required this.shortcutKey,
    required this.accentColor,
    required this.glowColor,
    required this.icon,
    required this.isFocused,
    required this.onTap,
    this.onHover,
  });

  @override
  State<_StudioLaunchCard> createState() => _StudioLaunchCardState();
}

class _StudioLaunchCardState extends State<_StudioLaunchCard> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isHighlighted = _isHovered || widget.isFocused;

    // 3D physical elevation & press displacement
    final double translateY = _isPressed
        ? 2.0
        : (isHighlighted ? -6.0 : 0.0);
    final double scale = _isPressed
        ? 0.985
        : (isHighlighted ? 1.025 : 1.0);

    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovered = true);
        widget.onHover?.call(true);
      },
      onExit: (_) {
        setState(() => _isHovered = false);
        widget.onHover?.call(false);
      },
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(0.0, translateY, 0.0)
            ..scaleByDouble(scale, scale, 1.0, 1.0),
          width: 275,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            // Specular gradient background (Dark Obsidian + Metallic sheen)
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                isHighlighted
                    ? widget.accentColor.withValues(alpha: 0.22)
                    : const Color(0xFF131B2E),
                const Color(0xFF0A0F1D),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            // Precision 3D Chamfer Border (Light shine at top, dark bevel at bottom)
            border: Border.all(
              color: isHighlighted
                  ? widget.glowColor
                  : const Color(0xFF334155).withValues(alpha: 0.6),
              width: isHighlighted ? 1.8 : 1.0,
            ),
            // Layered 3D Depth Shadows: Ambient Neon Glow + Deep Directional Shadow
            boxShadow: [
              BoxShadow(
                color: isHighlighted
                    ? widget.glowColor.withValues(alpha: 0.32)
                    : Colors.black.withValues(alpha: 0.45),
                blurRadius: isHighlighted ? 26 : 14,
                offset: Offset(0, isHighlighted ? 12 : 6),
              ),
              if (isHighlighted)
                BoxShadow(
                  color: widget.accentColor.withValues(alpha: 0.2),
                  blurRadius: 40,
                  spreadRadius: 2,
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Row: 3D Icon Badge & Category Pill
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 3D Metallic Icon Container
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          widget.accentColor,
                          widget.accentColor.withValues(alpha: 0.7),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: widget.glowColor.withValues(alpha: 0.45),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(widget.icon, size: 24, color: Colors.white),
                  ),

                  // Studio Category Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: widget.accentColor.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: widget.glowColor.withValues(alpha: 0.5),
                        width: 0.9,
                      ),
                    ),
                    child: Text(
                      widget.badge,
                      style: TextStyle(
                        color: widget.glowColor,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Studio Title
              Text(
                widget.title,
                style: const TextStyle(
                  color: Color(0xFFF8FAFC),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 3),

              // Studio Subtitle
              Text(
                widget.subtitle,
                style: TextStyle(
                  color: widget.glowColor,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),

              // Detailed Capabilities Description
              Text(
                widget.description,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),

              // Bottom 3D Action Strip: Shortcut hint + Animated Launch Button
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: isHighlighted
                      ? widget.accentColor.withValues(alpha: 0.18)
                      : const Color(0xFF030712).withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isHighlighted
                        ? widget.glowColor.withValues(alpha: 0.6)
                        : const Color(0xFF1E293B),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Launch',
                          style: TextStyle(
                            color: isHighlighted ? Colors.white : const Color(0xFFCBD5E1),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 4),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          transform: Matrix4.translationValues(isHighlighted ? 4.0 : 0.0, 0.0, 0.0),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            size: 13,
                            color: isHighlighted ? widget.glowColor : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),

                    // Keyboard Shortcut Key Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFF475569), width: 0.8),
                      ),
                      child: Text(
                        '[${widget.shortcutKey}]',
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 9.5,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Draws an aesthetic CAD Blueprint Grid in dark mode.
class _BlueprintGridBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final majorPaint = Paint()
      ..color = const Color(0xFF1E293B).withValues(alpha: 0.65)
      ..strokeWidth = 0.9;

    final minorPaint = Paint()
      ..color = const Color(0xFF131B2E).withValues(alpha: 0.85)
      ..strokeWidth = 0.5;

    const minorStep = 16.0;
    const majorStep = minorStep * 4;

    for (double x = 0; x <= size.width; x += minorStep) {
      final isMajor = (x % majorStep).abs() < 1.0;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), isMajor ? majorPaint : minorPaint);
    }

    for (double y = 0; y <= size.height; y += minorStep) {
      final isMajor = (y % majorStep).abs() < 1.0;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), isMajor ? majorPaint : minorPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Draws a laser cut trace around the perimeter during phase 1.
class _LaserCutTracePainter extends CustomPainter {
  final double progress;

  _LaserCutTracePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.0) return;

    final rect = Rect.fromCenter(
      center: Offset(size.width / 2.0, size.height / 2.0),
      width: size.width * 0.92,
      height: size.height * 0.92,
    );

    final path = Path()..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)));
    final pathMetric = path.computeMetrics().first;
    final extractPath = pathMetric.extractPath(0, pathMetric.length * progress);

    final tracePaint = Paint()
      ..color = const Color(0xFF38BDF8).withValues(alpha: 0.8)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    canvas.drawPath(extractPath, tracePaint);

    // Laser spark dot at cutting head
    final tangent = pathMetric.getTangentForOffset(pathMetric.length * progress);
    if (tangent != null) {
      final sparkCenter = tangent.position;
      final glowPaint = Paint()
        ..color = const Color(0xFF38BDF8).withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(sparkCenter, 5, glowPaint);

      final corePaint = Paint()..color = Colors.white;
      canvas.drawCircle(sparkCenter, 2.2, corePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LaserCutTracePainter old) => old.progress != progress;
}
