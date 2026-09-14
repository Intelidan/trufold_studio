// =============================================================================
// dsf_layer.dart
//
// Drawing Component Layer Specification for Danish Sheet Fold (.dsf) format.
// Defines layer properties (name, colorHex, lineType, strokeWidth, visibility,
// lock state) to retain CAD layer assignments across DSF save/read and DXF CAM.
// =============================================================================

class DsfLayer {
  final String name;
  final int colorHex;
  final String lineType;
  final double strokeWidth;
  final bool isVisible;
  final bool isLocked;
  final String? description;

  const DsfLayer({
    required this.name,
    this.colorHex = 0xFF0284C7,
    this.lineType = 'CONTINUOUS',
    this.strokeWidth = 1.0,
    this.isVisible = true,
    this.isLocked = false,
    this.description,
  });

  /// Standard CAD/CAM default layers for sheet metal fabrication
  static List<DsfLayer> defaultLayers() => const [
        DsfLayer(
          name: 'OUTLINE',
          colorHex: 0xFF0F172A,
          lineType: 'CONTINUOUS',
          strokeWidth: 2.0,
          description: 'Outer sheet blank perimeter cut',
        ),
        DsfLayer(
          name: 'BEND_UP',
          colorHex: 0xFF0284C7,
          lineType: 'DASHED',
          strokeWidth: 1.5,
          description: 'Positive press-brake bend line (UP)',
        ),
        DsfLayer(
          name: 'BEND_DOWN',
          colorHex: 0xFFD97706,
          lineType: 'DASHED',
          strokeWidth: 1.5,
          description: 'Negative press-brake bend line (DOWN)',
        ),
        DsfLayer(
          name: 'CUT',
          colorHex: 0xFFE11D48,
          lineType: 'CONTINUOUS',
          strokeWidth: 2.0,
          description: 'Laser cut slits, relief cuts, and notches',
        ),
        DsfLayer(
          name: 'HOLES',
          colorHex: 0xFF059669,
          lineType: 'CONTINUOUS',
          strokeWidth: 1.2,
          description: 'CNC punches, perforations, and bolt clearance holes',
        ),
        DsfLayer(
          name: '0',
          colorHex: 0xFF64748B,
          lineType: 'CONTINUOUS',
          strokeWidth: 1.0,
          description: 'Default base CAD layer',
        ),
        DsfLayer(
          name: 'ANNOTATION',
          colorHex: 0xFF6366F1,
          lineType: 'CONTINUOUS',
          strokeWidth: 1.0,
          description: 'Dimensions, titleblock, and bend angles',
        ),
      ];

  DsfLayer copyWith({
    String? name,
    int? colorHex,
    String? lineType,
    double? strokeWidth,
    bool? isVisible,
    bool? isLocked,
    String? description,
  }) {
    return DsfLayer(
      name: name ?? this.name,
      colorHex: colorHex ?? this.colorHex,
      lineType: lineType ?? this.lineType,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      isVisible: isVisible ?? this.isVisible,
      isLocked: isLocked ?? this.isLocked,
      description: description ?? this.description,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'colorHex': colorHex,
        'lineType': lineType,
        'strokeWidth': strokeWidth,
        'isVisible': isVisible,
        'isLocked': isLocked,
        if (description != null) 'description': description,
      };

  factory DsfLayer.fromJson(Map<String, dynamic> json) => DsfLayer(
        name: json['name'] as String? ?? '0',
        colorHex: json['colorHex'] as int? ?? 0xFF000000,
        lineType: json['lineType'] as String? ?? 'CONTINUOUS',
        strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 1.0,
        isVisible: json['isVisible'] as bool? ?? true,
        isLocked: json['isLocked'] as bool? ?? false,
        description: json['description'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DsfLayer &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          colorHex == other.colorHex &&
          lineType == other.lineType &&
          strokeWidth == other.strokeWidth &&
          isVisible == other.isVisible &&
          isLocked == other.isLocked;

  @override
  int get hashCode => Object.hash(name, colorHex, lineType, strokeWidth, isVisible, isLocked);
}
