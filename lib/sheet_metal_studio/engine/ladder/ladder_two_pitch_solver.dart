import '../../models/ladder/ladder_assembly_parameters.dart';

/// Output result of the industrial Two-Pitch calculation engine.
class LadderTwoPitchResult {
  final double effectiveSpan;
  final int bayCount;
  final int rungCount;
  final double actualIntermediatePitch;
  final double effectiveEndMargin;
  final List<double> rungStationsX;
  final List<String> validationWarnings;
  final bool isValid;

  const LadderTwoPitchResult({
    required this.effectiveSpan,
    required this.bayCount,
    required this.rungCount,
    required this.actualIntermediatePitch,
    required this.effectiveEndMargin,
    required this.rungStationsX,
    this.validationWarnings = const [],
    this.isValid = true,
  });
}

/// Solves the longitudinal rung placement array using header/footer end margins
/// and intermediate pitch distributions.
class LadderTwoPitchSolver {
  /// Solves the rung pattern for given parameters.
  static LadderTwoPitchResult solve(LadderAssemblyParameters params) {
    final warnings = <String>[];
    final length = params.length;
    final endMargin = params.endMarginPitch;
    final targetPitch = params.intermediateTargetPitch;

    // 1. Validation check on end margin
    if (endMargin < 50.0) {
      warnings.add(
        'End margin (${endMargin.toStringAsFixed(1)}mm) is less than 50mm minimum. '
        'Rungs may collide with coupler splice plates and M6 roofing bolts.',
      );
    }

    // 2. Compute effective span between the two end rungs
    final effectiveSpan = length - (2 * endMargin);
    if (effectiveSpan <= 50.0) {
      // Degenerate short length
      return LadderTwoPitchResult(
        effectiveSpan: 0.0,
        bayCount: 0,
        rungCount: 1,
        actualIntermediatePitch: 0.0,
        effectiveEndMargin: length / 2,
        rungStationsX: [length / 2],
        validationWarnings: ['Ladder length too short to support two end rungs.'],
        isValid: false,
      );
    }

    // 3. Number of intermediate bays (k)
    int k = (effectiveSpan / targetPitch).round();
    if (k < 1) k = 1;

    final int rungCount = k + 1;
    double actualPitch;
    double resolvedEndMargin;
    final stations = <double>[];

    if (params.pitchMode == RungPitchMode.equalizedPitch) {
      actualPitch = effectiveSpan / k;
      resolvedEndMargin = endMargin;
      for (int i = 0; i <= k; i++) {
        final val = resolvedEndMargin + (i * actualPitch);
        stations.add(double.parse(val.toStringAsFixed(3)));
      }
    } else {
      // Fixed pitch mode: strictly enforce P_target, floating the end margins
      actualPitch = targetPitch;
      final usedSpan = k * targetPitch;
      resolvedEndMargin = (length - usedSpan) / 2;
      for (int i = 0; i <= k; i++) {
        final val = resolvedEndMargin + (i * actualPitch);
        stations.add(double.parse(val.toStringAsFixed(3)));
      }
    }

    // 4. Industrial Standards Validation (NEMA VE-1 / IEC 61537)
    if (actualPitch > 450.0) {
      warnings.add(
        'Intermediate pitch (${actualPitch.toStringAsFixed(1)}mm) exceeds 450mm NEMA VE-1 max unsupported limit.',
      );
    } else if (actualPitch < 150.0) {
      warnings.add(
        'Intermediate pitch (${actualPitch.toStringAsFixed(1)}mm) is unusually dense (< 150mm), increasing weight and restricting cable ventilation.',
      );
    }

    return LadderTwoPitchResult(
      effectiveSpan: effectiveSpan,
      bayCount: k,
      rungCount: rungCount,
      actualIntermediatePitch: actualPitch,
      effectiveEndMargin: resolvedEndMargin,
      rungStationsX: stations,
      validationWarnings: warnings,
      isValid: warnings.isEmpty || (endMargin >= 50.0 && actualPitch <= 500.0),
    );
  }
}
