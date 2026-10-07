// =============================================================================
// cad_primitives.dart
//
// Standalone 2D and 3D geometric primitives for Sheet Metal Studio.
// Designed with zero dependencies on external app code so this entire module
// can be copied into any standalone Flutter/Dart application.
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

export 'cad_geometry.dart' show CadArc2D;
export 'cad_material_preset.dart';

import 'cad_material_preset.dart';

/// 2D Coordinate Point (in mm)
@immutable
class CadPoint2D {
  final double x;
  final double y;

  const CadPoint2D(this.x, this.y);

  CadPoint2D operator +(CadPoint2D other) => CadPoint2D(x + other.x, y + other.y);
  CadPoint2D operator -(CadPoint2D other) => CadPoint2D(x - other.x, y - other.y);
  CadPoint2D operator *(double scale) => CadPoint2D(x * scale, y * scale);
  CadPoint2D operator /(double divisor) => CadPoint2D(x / divisor, y / divisor);

  double get length => math.sqrt(x * x + y * y);

  double distanceTo(CadPoint2D other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  Offset toOffset() => Offset(x, y);

  Map<String, dynamic> toJson() => {'x': x, 'y': y};
  factory CadPoint2D.fromJson(Map<String, dynamic> json) => CadPoint2D((json['x'] as num).toDouble(), (json['y'] as num).toDouble());

  @override
  String toString() => 'CadPoint2D($x, $y)';

  @override
  bool operator ==(Object other) => identical(this, other) || other is CadPoint2D && (x - other.x).abs() < 1e-4 && (y - other.y).abs() < 1e-4;

  @override
  int get hashCode => Object.hash(x.round(), y.round());
}

/// 3D Coordinate Point (in mm)
@immutable
class CadPoint3D {
  final double x;
  final double y;
  final double z;

  const CadPoint3D(this.x, this.y, this.z);

  CadPoint3D operator +(CadPoint3D other) => CadPoint3D(x + other.x, y + other.y, z + other.z);
  CadPoint3D operator -(CadPoint3D other) => CadPoint3D(x - other.x, y - other.y, z - other.z);
  CadPoint3D operator *(double scale) => CadPoint3D(x * scale, y * scale, z * scale);
  CadPoint3D operator /(double divisor) => CadPoint3D(x / divisor, y / divisor, z / divisor);

  double dot(CadPoint3D other) => x * other.x + y * other.y + z * other.z;

  CadPoint3D cross(CadPoint3D other) => CadPoint3D(y * other.z - z * other.y, z * other.x - x * other.z, x * other.y - y * other.x);

  double get length => math.sqrt(x * x + y * y + z * z);
  double distanceTo(CadPoint3D other) => (this - other).length;

  CadPoint3D normalized() {
    final len = length;
    if (len < 1e-6) return const CadPoint3D(0, 0, 1);
    return CadPoint3D(x / len, y / len, z / len);
  }

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'z': z};
  factory CadPoint3D.fromJson(Map<String, dynamic> json) =>
      CadPoint3D((json['x'] as num).toDouble(), (json['y'] as num).toDouble(), (json['z'] as num).toDouble());

  @override
  String toString() => 'CadPoint3D($x, $y, $z)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is CadPoint3D && (x - other.x).abs() < 1e-4 && (y - other.y).abs() < 1e-4 && (z - other.z).abs() < 1e-4;

  @override
  int get hashCode => Object.hash(x.round(), y.round(), z.round());
}

/// 3D Polygon Face for Shaded Rendering
class CadFoldedPolygon3D {
  final String faceId;
  final List<CadPoint3D> vertices;
  final CadPoint3D normal;
  final Color color;
  final bool drawWireframe;
  final List<List<CadPoint3D>> holes;
  final List<String> holePunchIds;
  final List<List<CadPoint3D>> cutSegments;
  final List<List<CadPoint3D>> boundaryLines;
  final List<List<CadPoint3D>> tangentLines;

  const CadFoldedPolygon3D({
    required this.faceId,
    required this.vertices,
    required this.normal,
    this.color = const Color(0xFFB0BEC5),
    this.drawWireframe = true,
    this.holes = const [],
    this.holePunchIds = const [],
    this.cutSegments = const [],
    this.boundaryLines = const [],
    this.tangentLines = const [],
  });
}

/// 2D Line Segment (used for Laser Cut Lines, Slits, Partition Edges)
@immutable
class CadLineSegment {
  final String id;
  final CadPoint2D p1;
  final CadPoint2D p2;
  final String layer;
  final bool showLabel;

  const CadLineSegment({required this.id, required this.p1, required this.p2, this.layer = 'CUT', this.showLabel = true});

  double get x1 => p1.x;
  double get y1 => p1.y;
  double get x2 => p2.x;
  double get y2 => p2.y;
  bool get isVisible => true;

  double get length => p1.distanceTo(p2);
  double get angleRad => math.atan2(p2.y - p1.y, p2.x - p1.x);
  double get angleDeg => angleRad * 180.0 / math.pi;
  CadPoint2D get midpoint => CadPoint2D((p1.x + p2.x) / 2.0, (p1.y + p2.y) / 2.0);

  CadLineSegment copyWith({String? id, CadPoint2D? p1, CadPoint2D? p2, String? layer, bool? showLabel}) {
    return CadLineSegment(id: id ?? this.id, p1: p1 ?? this.p1, p2: p2 ?? this.p2, layer: layer ?? this.layer, showLabel: showLabel ?? this.showLabel);
  }

  Map<String, dynamic> toJson() => {'id': id, 'p1': p1.toJson(), 'p2': p2.toJson(), 'layer': layer, 'showLabel': showLabel};

  factory CadLineSegment.fromJson(Map<String, dynamic> json) => CadLineSegment(
    id: json['id'] as String? ?? 'C1',
    p1: CadPoint2D.fromJson(json['p1'] as Map<String, dynamic>),
    p2: CadPoint2D.fromJson(json['p2'] as Map<String, dynamic>),
    layer: json['layer'] as String? ?? 'CUT',
    showLabel: json['showLabel'] as bool? ?? true,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CadLineSegment &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          p1 == other.p1 &&
          p2 == other.p2 &&
          layer == other.layer &&
          showLabel == other.showLabel;

  @override
  int get hashCode => Object.hash(id, p1, p2, layer, showLabel);

  @override
  String toString() => 'CadLineSegment($id, p1: $p1, p2: $p2, layer: $layer, showLabel: $showLabel)';
}

/// Visual shading and illustration styles for CAD 3D rendering.
enum CadShadingStyle {
  realisticPbr(
    'Industrial PBR Metal',
    'Physically-based metallic shading with realistic specular highlights and shadows.',
  ),
  celShaded2D(
    '2D Anime / Drawn Illustration',
    'Non-photorealistic cel shading with quantized light bands and crisp inked outlines, mimicking 2D animation style.',
  ),
  technicalBlueprint(
    'Technical Blueprint',
    'Crisp blueprint drawing style with cool technical tint and highlighted boundary features.',
  );

  final String label;
  final String description;
  const CadShadingStyle(this.label, this.description);
}

/// Anti-aliasing detail levels and resolution supersampling factors.
enum AntiAliasingQuality {
  off('Off', 1.0),
  standard('Standard (MSAA)', 1.0),
  high('High (1.5x)', 1.5),
  ultra('Ultra (2x SSAA)', 2.0),
  extreme('Extreme (3x SSAA)', 3.0);

  final String label;
  final double pixelRatioScale;
  const AntiAliasingQuality(this.label, this.pixelRatioScale);
}

/// CAD Surface & Edge Render Modes matching Onshape View Context Menu.
enum OnshapeRenderMode {
  shadedWithEdges('Shaded with edges'),
  shadedWithoutEdges('Shaded without edges'),
  unshaded('Unshaded'),
  translucent('Translucent');

  final String label;
  const OnshapeRenderMode(this.label);
}

/// Mode for rendering tangent edges (fillet transitions) on CAD parts.
enum OnshapeTangentEdgeMode {
  visible('Tangent edges visible'),
  phantom('Tangent edges phantom'),
  removed('Tangent edges removed');

  final String label;
  const OnshapeTangentEdgeMode(this.label);
}

/// Active 3D CAD rendering engine backend for TruFold Studio.
enum Cad3dEngineMode {
  flutterGpu(
    'Flutter GPU (Scene)',
    'Hardware-accelerated 120 FPS PBR renderer powered by flutter_scene and Impeller.',
  ),
  flutterPaint(
    'Flutter Paint (2.5D Canvas)',
    '1st-generation pure software Canvas CustomPainter fallback with zero GPU dependencies.',
  );

  final String label;
  final String description;
  const Cad3dEngineMode(this.label, this.description);
}

/// Preserves independent 3D camera pan, zoom, orbit distance, and angles across multiple open tabs.
class Cad3dCameraState {
  final double azimuthDeg;
  final double elevationDeg;
  final double zoom;
  final Offset pan;
  final double orbitDistance;
  final CadPoint3D orbitTarget;
  final bool isInitialized;

  const Cad3dCameraState({
    this.azimuthDeg = 45.0,
    this.elevationDeg = 35.264,
    this.zoom = 1.0,
    this.pan = Offset.zero,
    this.orbitDistance = 350.0,
    this.orbitTarget = const CadPoint3D(0, 0, 0),
    this.isInitialized = false,
  });

  double get panX => pan.dx;
  double get panY => pan.dy;
}

/// Onshape-compatible 3D Graphics Preferences.
/// Configures viewport lighting/FOV, shaded body surface properties, and phantom edge lines.
class OnshapeGraphicsPreferences {
  // Viewport Settings
  final double ambientOcclusion; // 0% to 100%, default 40%
  final double fieldOfView; // 15 deg to 90 deg, default 46 deg
  final AntiAliasingQuality antiAliasingQuality; // Viewport anti-aliasing & SSAA level

  // Shaded Bodies Settings
  final double lineWidth; // 0.5 px to 5.0 px, default 1.3 px
  final double shininess; // 0% to 100%, default 25% (as seen in Onshape SS2)
  final Color specularColor; // default 0xFFFFFFFF (crisp white specular glare)
  final Color sectionInterferenceColor; // default 0xFF4CAF50

  // Phantom Edges Settings
  final double phantomTangentEdgeWidth; // 0.5 px to 4.0 px, default 0.8 px
  final Color phantomTangentEdgeColor; // default 0xFF212121
  final OnshapeTangentEdgeMode tangentEdgeMode; // default: phantom

  // Part Appearance
  final bool useOnshapeCadColor; // default true (Onshape slate steel-blue 0x70A5C2)
  final bool hiddenEdgesVisible; // default false

  // Studio Lighting Controls (Global lighting addition, removal, and spherical roaming)
  final double lightAzimuthDeg; // 0 deg to 360 deg, default 45 deg
  final double lightElevationDeg; // 10 deg to 90 deg, default 55 deg
  final double keyLightIntensity; // 0.0 to 3.0, default 1.45
  final bool hasSecondaryLight; // toggle secondary fill light, default true
  final bool hasBackLight; // toggle rim/back light, default false

  // PBR / Shader Material Settings (Hot-Dip Galvanized, Pre-Galvanized, Plastic, Chrome, etc.)
  final CadMaterialSettings materialSettings;

  const OnshapeGraphicsPreferences({
    this.ambientOcclusion = 40.0,
    this.fieldOfView = 46.0,
    this.antiAliasingQuality = AntiAliasingQuality.extreme,
    this.lineWidth = 0.65,
    this.shininess = 25.0,
    this.specularColor = const Color(0xFFFFFFFF),
    this.sectionInterferenceColor = const Color(0xFF4CAF50),
    this.phantomTangentEdgeWidth = 0.8,
    this.phantomTangentEdgeColor = const Color(0xFF212121),
    this.tangentEdgeMode = OnshapeTangentEdgeMode.phantom,
    this.useOnshapeCadColor = true,
    this.hiddenEdgesVisible = false,
    this.lightAzimuthDeg = 45.0,
    this.lightElevationDeg = 55.0,
    this.keyLightIntensity = 1.45,
    this.hasSecondaryLight = true,
    this.hasBackLight = false,
    this.materialSettings = const CadMaterialSettings(),
  });

  OnshapeGraphicsPreferences copyWith({
    double? ambientOcclusion,
    double? fieldOfView,
    AntiAliasingQuality? antiAliasingQuality,
    double? lineWidth,
    double? shininess,
    Color? specularColor,
    Color? sectionInterferenceColor,
    double? phantomTangentEdgeWidth,
    Color? phantomTangentEdgeColor,
    OnshapeTangentEdgeMode? tangentEdgeMode,
    bool? useOnshapeCadColor,
    bool? hiddenEdgesVisible,
    double? lightAzimuthDeg,
    double? lightElevationDeg,
    double? keyLightIntensity,
    bool? hasSecondaryLight,
    bool? hasBackLight,
    CadMaterialSettings? materialSettings,
  }) {
    return OnshapeGraphicsPreferences(
      ambientOcclusion: ambientOcclusion ?? this.ambientOcclusion,
      fieldOfView: fieldOfView ?? this.fieldOfView,
      antiAliasingQuality: antiAliasingQuality ?? this.antiAliasingQuality,
      lineWidth: lineWidth ?? this.lineWidth,
      shininess: shininess ?? this.shininess,
      specularColor: specularColor ?? this.specularColor,
      sectionInterferenceColor: sectionInterferenceColor ?? this.sectionInterferenceColor,
      phantomTangentEdgeWidth: phantomTangentEdgeWidth ?? this.phantomTangentEdgeWidth,
      phantomTangentEdgeColor: phantomTangentEdgeColor ?? this.phantomTangentEdgeColor,
      tangentEdgeMode: tangentEdgeMode ?? this.tangentEdgeMode,
      useOnshapeCadColor: useOnshapeCadColor ?? this.useOnshapeCadColor,
      hiddenEdgesVisible: hiddenEdgesVisible ?? this.hiddenEdgesVisible,
      lightAzimuthDeg: lightAzimuthDeg ?? this.lightAzimuthDeg,
      lightElevationDeg: lightElevationDeg ?? this.lightElevationDeg,
      keyLightIntensity: keyLightIntensity ?? this.keyLightIntensity,
      hasSecondaryLight: hasSecondaryLight ?? this.hasSecondaryLight,
      hasBackLight: hasBackLight ?? this.hasBackLight,
      materialSettings: materialSettings ?? this.materialSettings,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is OnshapeGraphicsPreferences &&
        other.ambientOcclusion == ambientOcclusion &&
        other.fieldOfView == fieldOfView &&
        other.antiAliasingQuality == antiAliasingQuality &&
        other.lineWidth == lineWidth &&
        other.shininess == shininess &&
        other.specularColor == specularColor &&
        other.sectionInterferenceColor == sectionInterferenceColor &&
        other.phantomTangentEdgeWidth == phantomTangentEdgeWidth &&
        other.phantomTangentEdgeColor == phantomTangentEdgeColor &&
        other.tangentEdgeMode == tangentEdgeMode &&
        other.useOnshapeCadColor == useOnshapeCadColor &&
        other.hiddenEdgesVisible == hiddenEdgesVisible &&
        other.lightAzimuthDeg == lightAzimuthDeg &&
        other.lightElevationDeg == lightElevationDeg &&
        other.keyLightIntensity == keyLightIntensity &&
        other.hasSecondaryLight == hasSecondaryLight &&
        other.hasBackLight == hasBackLight &&
        other.materialSettings == materialSettings;
  }

  @override
  int get hashCode => Object.hash(
        ambientOcclusion,
        fieldOfView,
        antiAliasingQuality,
        lineWidth,
        shininess,
        specularColor,
        sectionInterferenceColor,
        phantomTangentEdgeWidth,
        phantomTangentEdgeColor,
        tangentEdgeMode,
        useOnshapeCadColor,
        hiddenEdgesVisible,
        lightAzimuthDeg,
        lightElevationDeg,
        keyLightIntensity,
        hasSecondaryLight,
        hasBackLight,
        materialSettings,
      );
}

