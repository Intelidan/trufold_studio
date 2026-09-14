// =============================================================================
// corner_treatment.dart
//
// Corner Chamfers and Fillets for Sheet Metal Blank outer contour.
// =============================================================================

enum CornerType {
  fillet,  // Curved corner (tool radius R)
  chamfer, // Mitered corner (45° or custom cut distance)
}

class CornerTreatment {
  final int vertexIndex;
  final CornerType type;
  final double sizeMm;

  const CornerTreatment({
    required this.vertexIndex,
    this.type = CornerType.fillet,
    this.sizeMm = 5.0,
  });

  Map<String, dynamic> toJson() => {
        'vertexIndex': vertexIndex,
        'type': type.name,
        'sizeMm': sizeMm,
      };

  factory CornerTreatment.fromJson(Map<String, dynamic> json) => CornerTreatment(
        vertexIndex: json['vertexIndex'] as int? ?? 0,
        type: CornerType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => CornerType.fillet,
        ),
        sizeMm: (json['sizeMm'] as num?)?.toDouble() ?? 5.0,
      );
}
