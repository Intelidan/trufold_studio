import '../../sheet_metal_studio/models/cad_primitives.dart';

/// Anomaly detected during manual welding stroke (speed, weaving, burn-through).
class WeldAnomaly {
  final CadPoint3D position;
  final String description;
  final double severity; // 0.0 to 1.0

  const WeldAnomaly({required this.position, required this.description, this.severity = 0.5});

  Map<String, dynamic> toJson() => {
    'position': {'x': position.x, 'y': position.y, 'z': position.z},
    'description': description,
    'severity': severity,
  };

  factory WeldAnomaly.fromJson(Map<String, dynamic> json) {
    final p = json['position'] as Map<String, dynamic>;
    return WeldAnomaly(
      position: CadPoint3D((p['x'] as num).toDouble(), (p['y'] as num).toDouble(), (p['z'] as num).toDouble()),
      description: json['description'] as String,
      severity: (json['severity'] as num?)?.toDouble() ?? 0.5,
    );
  }
}

/// Evaluation score and diagnostic feedback for a welding bead.
class WeldScoreResult {
  final double speedConsistency; // 0.0 to 100.0%
  final double profileUniformity; // 0.0 to 100.0%
  final double overallScore; // 0.0 to 100.0%
  final String gradeFeedback;
  final List<WeldAnomaly> anomalies;

  const WeldScoreResult({
    required this.speedConsistency,
    required this.profileUniformity,
    required this.overallScore,
    required this.gradeFeedback,
    this.anomalies = const [],
  });

  String get letterGrade {
    if (overallScore >= 95.0) return 'A+';
    if (overallScore >= 85.0) return 'A';
    if (overallScore >= 75.0) return 'B';
    if (overallScore >= 60.0) return 'C';
    return 'F';
  }

  Map<String, dynamic> toJson() => {
    'speedConsistency': speedConsistency,
    'profileUniformity': profileUniformity,
    'overallScore': overallScore,
    'gradeFeedback': gradeFeedback,
    'anomalies': anomalies.map((a) => a.toJson()).toList(),
  };

  factory WeldScoreResult.fromJson(Map<String, dynamic> json) => WeldScoreResult(
    speedConsistency: (json['speedConsistency'] as num).toDouble(),
    profileUniformity: (json['profileUniformity'] as num).toDouble(),
    overallScore: (json['overallScore'] as num).toDouble(),
    gradeFeedback: json['gradeFeedback'] as String,
    anomalies: (json['anomalies'] as List<dynamic>?)?.map((e) => WeldAnomaly.fromJson(e as Map<String, dynamic>)).toList() ?? const [],
  );
}
