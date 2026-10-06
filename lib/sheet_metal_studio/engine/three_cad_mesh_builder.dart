import 'dart:math' as math;

import 'package:three_js/three_js.dart' as three;
import 'package:three_js_geometry/three_js_geometry.dart' as three_geo;

import '../models/cad_primitives.dart';
import 'kinematic_fold_engine.dart';

/// High-Performance Hardware CAD Mesh Builder for TruFold Studio.
/// Consolidates all model facets into high-speed batched [three.BufferGeometry] meshes
/// with GPU Depth Testing (Z-buffer), metallic PBR shading, and crisp boundary edges.
/// Eliminates per-polygon draw calls to achieve 120 FPS buttery smooth orbit performance.
class ThreeCadMeshBuilder {
  /// Builds a high-speed hardware-accelerated 3D model from a [FoldedMeshResult].
  static three.Group buildCadModel(
    FoldedMeshResult meshResult, {
    String? selectedFaceId,
    String? hoveredFaceId,
    String? selectedPunchId,
    String? hoveredPunchId,
    bool showWireframe = true,
    bool showBorderLines = true,
    bool isObstructedXRayMode = false,
    CadShadingStyle shadingStyle = CadShadingStyle.realisticPbr,
    OnshapeGraphicsPreferences preferences = const OnshapeGraphicsPreferences(),
    OnshapeRenderMode renderMode = OnshapeRenderMode.shadedWithEdges,
  }) {
    final rootGroup = three.Group();
    final pivot = meshResult.center;

    // Sub-group for shaded faces
    final facesGroup = three.Group();
    // Sub-group for crisp boundary lines and laser cuts
    final edgesGroup = three.Group();

    // Batched vertex buffers for primary solid body (single draw call)
    final mainPositions = <double>[];
    final mainNormals = <double>[];
    final mainColors = <double>[];

    // Batched vertex buffers for highlighted faces (selected / hovered)
    final highlightPositions = <double>[];
    final highlightNormals = <double>[];
    final highlightColors = <double>[];

    final edgeRibbonPositions = <double>[];
    final edgeRibbonNormals = <double>[];
    final phantomRibbonPositions = <double>[];
    final phantomRibbonNormals = <double>[];

    final lineCoords = <double>[];
    final tangentCoords = <double>[];
    final phantomTangentCoords = <double>[];
    final laserCutCoords = <double>[];

    final modelSpan = math.max(meshResult.boundWidth, math.max(meshResult.boundLength, meshResult.boundHeight));
    // World mm corresponding to approximately 1 screen pixel at default camera framing
    final pxInWorld = math.max(0.25, (modelSpan > 10.0 ? modelSpan : 400.0) / 750.0);
    final ribbonWidth = preferences.lineWidth * pxInWorld;

    for (final poly in meshResult.allPolygons) {
      if (poly.vertices.length < 3) continue;

      final isSelected = (poly.faceId == selectedFaceId);
      final isHovered = (poly.faceId == hoveredFaceId);
      final isHighlighted = isSelected || isHovered;

      final targetPositions = isHighlighted ? highlightPositions : mainPositions;
      final targetNormals = isHighlighted ? highlightNormals : mainNormals;
      final targetColors = isHighlighted ? highlightColors : mainColors;

      // Color selection
      double cr, cg, cb;
      if (isSelected) {
        cr = 0.22;
        cg = 0.74;
        cb = 0.97; // Sky blue highlight (0x38BDF8)
      } else if (isHovered) {
        cr = 0.73;
        cg = 0.90;
        cb = 0.99; // Cyan hover (0xBAE6FD)
      } else {
        if (preferences.useOnshapeCadColor) {
          // Authentic Onshape Darker Slate Steel-Blue: RGB (71, 122, 166) -> #477AA6
          final isNeutralMetal = (poly.color.r - poly.color.g).abs() < 0.15 && (poly.color.g - poly.color.b).abs() < 0.15;
          if (isNeutralMetal || preferences.useOnshapeCadColor) {
            cr = 0.280; // 71 / 255.0
            cg = 0.480; // 122 / 255.0
            cb = 0.650; // 166 / 255.0
          } else {
            cr = poly.color.r;
            cg = poly.color.g;
            cb = poly.color.b;
          }
        } else {
          cr = poly.color.r;
          cg = poly.color.g;
          cb = poly.color.b;
        }
      }

      if (poly.holes.isEmpty) {
        // Fast-path: Convex / simple planar polygon fan triangulation (zero Earcut overhead)
        final nx = poly.normal.x;
        final ny = poly.normal.y;
        final nz = poly.normal.z;
        final v0 = poly.vertices[0];
        final v0x = v0.x - pivot.x;
        final v0y = v0.y - pivot.y;
        final v0z = v0.z - pivot.z;

        for (int i = 1; i < poly.vertices.length - 1; i++) {
          final v1 = poly.vertices[i];
          final v2 = poly.vertices[i + 1];

          targetPositions.addAll([v0x, v0y, v0z, v1.x - pivot.x, v1.y - pivot.y, v1.z - pivot.z, v2.x - pivot.x, v2.y - pivot.y, v2.z - pivot.z]);
          targetNormals.addAll([nx, ny, nz, nx, ny, nz, nx, ny, nz]);
          targetColors.addAll([cr, cg, cb, cr, cg, cb, cr, cg, cb]);
        }
      } else {
        // Polygon with inner cutout holes (punch openings, slots, perforations)
        _triangulateHolePolygon(
          poly,
          pivot: pivot,
          outPositions: targetPositions,
          outNormals: targetNormals,
          outColors: targetColors,
          colorR: cr,
          colorG: cg,
          colorB: cb,
        );
      }

      // Collect boundary lines for hardware edge rendering
      if (showWireframe && showBorderLines) {
        for (final seg in poly.boundaryLines) {
          if (seg.length >= 2) {
            for (int i = 0; i < seg.length - 1; i++) {
              _appendLineWithWidth(seg[i], seg[i + 1], pivot, poly.normal, preferences.lineWidth, lineCoords, pxInWorld: pxInWorld);
              _appendRibbonQuad(seg[i], seg[i + 1], pivot, poly.normal, ribbonWidth, edgeRibbonPositions, edgeRibbonNormals, pxInWorld: pxInWorld);
            }
          }
        }

        // Collect tangent edges (fillet transitions)
        if (preferences.tangentEdgeMode != OnshapeTangentEdgeMode.removed) {
          final phantomWidth = preferences.phantomTangentEdgeWidth * pxInWorld;
          for (final seg in poly.tangentLines) {
            if (seg.length >= 2) {
              for (int i = 0; i < seg.length - 1; i++) {
                if (preferences.tangentEdgeMode == OnshapeTangentEdgeMode.phantom) {
                  _appendPhantomDashes(seg[i], seg[i + 1], pivot, phantomTangentCoords);
                  _appendPhantomDashRibbons(seg[i], seg[i + 1], pivot, poly.normal, phantomWidth, phantomRibbonPositions, phantomRibbonNormals, pxInWorld: pxInWorld);
                } else {
                  _appendLineWithWidth(seg[i], seg[i + 1], pivot, poly.normal, preferences.lineWidth, tangentCoords, pxInWorld: pxInWorld);
                  _appendRibbonQuad(seg[i], seg[i + 1], pivot, poly.normal, ribbonWidth, edgeRibbonPositions, edgeRibbonNormals, pxInWorld: pxInWorld);
                }
              }
            }
          }
        }
      }

      // Collect laser cut traces
      for (final seg in poly.cutSegments) {
        if (seg.length >= 2) {
          for (int i = 0; i < seg.length - 1; i++) {
            laserCutCoords.addAll([
              seg[i].x - pivot.x,
              seg[i].y - pivot.y,
              seg[i].z - pivot.z,
              seg[i + 1].x - pivot.x,
              seg[i + 1].y - pivot.y,
              seg[i + 1].z - pivot.z,
            ]);
            if (showWireframe && showBorderLines) {
              _appendRibbonQuad(seg[i], seg[i + 1], pivot, poly.normal, ribbonWidth, edgeRibbonPositions, edgeRibbonNormals, pxInWorld: pxInWorld);
            }
          }
        }
      }
    }

    // 1. Shaded Solid Body Mesh (Single draw call for all regular faces)
    final isTranslucent = (renderMode == OnshapeRenderMode.translucent);
    final isUnshaded = (renderMode == OnshapeRenderMode.unshaded);
    final isWithoutEdges = (renderMode == OnshapeRenderMode.shadedWithoutEdges);

    if (mainPositions.isNotEmpty && !isUnshaded) {
      final mainGeo = three.BufferGeometry();
      mainGeo.setAttribute(three.Attribute.position, three.Float32BufferAttribute.fromList(mainPositions, 3));
      mainGeo.setAttribute(three.Attribute.normal, three.Float32BufferAttribute.fromList(mainNormals, 3));
      mainGeo.setAttribute(three.Attribute.color, three.Float32BufferAttribute.fromList(mainColors, 3));

      // In Onshape CAD, sheet metal has a solid dielectric surface with gloss reflection
      final shininessNorm = (preferences.shininess / 100.0).clamp(0.0, 1.0);
      final roughness = (0.72 - shininessNorm * 0.67).clamp(0.04, 0.95);
      final metalness = (shininessNorm * 0.12).clamp(0.0, 0.20);

      three.Material mainMat;
      if (shadingStyle == CadShadingStyle.celShaded2D) {
        // 2D Anime / Cartoon Drawing Cel Shading (Quantized discrete lighting)
        mainMat = three.MeshToonMaterial.fromMap({
          'vertexColors': true,
          'side': three.DoubleSide,
          'depthTest': true,
          'depthWrite': !isTranslucent,
          if (isTranslucent) 'transparent': true,
          if (isTranslucent) 'opacity': 0.35,
        });
      } else if (shadingStyle == CadShadingStyle.technicalBlueprint) {
        mainMat = three.MeshStandardMaterial.fromMap({
          'vertexColors': true,
          'roughness': 0.65,
          'metalness': 0.15,
          'side': three.DoubleSide,
          'depthTest': true,
          'depthWrite': !isTranslucent,
          if (isTranslucent) 'transparent': true,
          if (isTranslucent) 'opacity': 0.35,
        });
      } else {
        // Default: Onshape PBR Metallic Shading with live Shininess control
        mainMat = three.MeshStandardMaterial.fromMap({
          'vertexColors': true,
          'roughness': roughness,
          'metalness': metalness,
          'side': three.DoubleSide,
          'depthTest': true,
          'depthWrite': !isTranslucent,
          if (isTranslucent) 'transparent': true,
          if (isTranslucent) 'opacity': 0.35,
        });
      }
      facesGroup.add(three.Mesh(mainGeo, mainMat));

      // Pass 2: Smart Obstructed X-Ray / Hidden Feature Transparency
      if (isObstructedXRayMode && !isTranslucent) {
        final obsMat = three.MeshBasicMaterial.fromMap({
          'color': 0x0284C7, // Blueprint translucent cyan
          'transparent': true,
          'opacity': 0.32,
          'depthTest': true,
          'depthWrite': false,
          'side': three.DoubleSide,
        });
        obsMat.depthFunc = three.GreaterDepth;
        facesGroup.add(three.Mesh(mainGeo, obsMat));
      }
    }

    // 2. Highlight Mesh (Single draw call for any selected or hovered faces)
    if (highlightPositions.isNotEmpty && !isUnshaded) {
      final hlGeo = three.BufferGeometry();
      hlGeo.setAttribute(three.Attribute.position, three.Float32BufferAttribute.fromList(highlightPositions, 3));
      hlGeo.setAttribute(three.Attribute.normal, three.Float32BufferAttribute.fromList(highlightNormals, 3));
      hlGeo.setAttribute(three.Attribute.color, three.Float32BufferAttribute.fromList(highlightColors, 3));

      three.Material hlMat;
      if (shadingStyle == CadShadingStyle.celShaded2D) {
        hlMat = three.MeshToonMaterial.fromMap({'vertexColors': true, 'side': three.DoubleSide, 'depthTest': true, 'depthWrite': true});
      } else {
        hlMat = three.MeshStandardMaterial.fromMap({
          'vertexColors': true,
          'roughness': 0.25,
          'metalness': 0.25,
          'side': three.DoubleSide,
          'depthTest': true,
          'depthWrite': true,
        });
      }
      facesGroup.add(three.Mesh(hlGeo, hlMat));
    }

    if (!isUnshaded) {
      rootGroup.add(facesGroup);
    }

    // 3. Batch-rendered outline edges (single draw call)
    final shouldRenderEdges = !isWithoutEdges && showWireframe && showBorderLines && preferences.lineWidth > 0.01;
    if (shouldRenderEdges) {
      final int edgeColor = shadingStyle == CadShadingStyle.celShaded2D
          ? 0x0F172A // Rich black-slate ink
          : (shadingStyle == CadShadingStyle.technicalBlueprint ? 0x0284C7 : 0x1E293B);

      // 3a. Thick Antialiased MSAA Edge Ribbons (Scalable with Line Width Slider)
      if (edgeRibbonPositions.isNotEmpty) {
        final ribbonGeo = three.BufferGeometry();
        ribbonGeo.setAttribute(three.Attribute.position, three.Float32BufferAttribute.fromList(edgeRibbonPositions, 3));
        ribbonGeo.setAttribute(three.Attribute.normal, three.Float32BufferAttribute.fromList(edgeRibbonNormals, 3));
        final ribbonMat = three.MeshBasicMaterial.fromMap({
          'color': edgeColor,
          'side': three.DoubleSide,
          'depthTest': true,
          'depthWrite': false,
          'polygonOffset': true,
          'polygonOffsetFactor': -2.0,
          'polygonOffsetUnits': -4.0,
        });
        edgesGroup.add(three.Mesh(ribbonGeo, ribbonMat));
      }

      // 3b. Thick Antialiased Phantom Dash Ribbons
      if (phantomRibbonPositions.isNotEmpty) {
        final phantomRibbonGeo = three.BufferGeometry();
        phantomRibbonGeo.setAttribute(three.Attribute.position, three.Float32BufferAttribute.fromList(phantomRibbonPositions, 3));
        phantomRibbonGeo.setAttribute(three.Attribute.normal, three.Float32BufferAttribute.fromList(phantomRibbonNormals, 3));
        final phantomColor = (preferences.phantomTangentEdgeColor.toARGB32() & 0x00FFFFFF);
        final phantomRibbonMat = three.MeshBasicMaterial.fromMap({
          'color': phantomColor,
          'side': three.DoubleSide,
          'depthTest': true,
          'depthWrite': false,
          'polygonOffset': true,
          'polygonOffsetFactor': -2.0,
          'polygonOffsetUnits': -4.0,
        });
        edgesGroup.add(three.Mesh(phantomRibbonGeo, phantomRibbonMat));
      }

      // 3c. Crisp 1px Core Centerlines (Fallback & Maximum Edge-On Sharpness)
      if (lineCoords.isNotEmpty) {
        final edgeGeo = three.BufferGeometry();
        edgeGeo.setAttribute(three.Attribute.position, three.Float32BufferAttribute.fromList(lineCoords, 3));
        final edgeMat = three.LineBasicMaterial.fromMap({'color': edgeColor, 'depthTest': true, 'depthWrite': false});
        edgesGroup.add(three.LineSegments(edgeGeo, edgeMat));
      }

      if (tangentCoords.isNotEmpty) {
        final tanGeo = three.BufferGeometry();
        tanGeo.setAttribute(three.Attribute.position, three.Float32BufferAttribute.fromList(tangentCoords, 3));
        final tanMat = three.LineBasicMaterial.fromMap({'color': edgeColor, 'depthTest': true, 'depthWrite': false});
        edgesGroup.add(three.LineSegments(tanGeo, tanMat));
      }

      if (phantomTangentCoords.isNotEmpty) {
        final phantomGeo = three.BufferGeometry();
        phantomGeo.setAttribute(three.Attribute.position, three.Float32BufferAttribute.fromList(phantomTangentCoords, 3));
        final phantomColor = (preferences.phantomTangentEdgeColor.toARGB32() & 0x00FFFFFF);
        final phantomMat = three.LineBasicMaterial.fromMap({'color': phantomColor, 'depthTest': true, 'depthWrite': false});
        edgesGroup.add(three.LineSegments(phantomGeo, phantomMat));
      }

      // 3d. Obstructed / Hidden Edges (when Hidden Edges Visible is active)
      if (preferences.hiddenEdgesVisible) {
        final allHidden = [...lineCoords, ...tangentCoords, ...phantomTangentCoords];
        if (allHidden.isNotEmpty) {
          final obsGeo = three.BufferGeometry();
          obsGeo.setAttribute(three.Attribute.position, three.Float32BufferAttribute.fromList(allHidden, 3));
          final obsMat = three.LineBasicMaterial.fromMap({
            'color': (preferences.phantomTangentEdgeColor.toARGB32() & 0x00FFFFFF),
            'linewidth': preferences.phantomTangentEdgeWidth,
            'transparent': true,
            'opacity': 0.40,
            'depthTest': true,
            'depthWrite': false,
          });
          obsMat.depthFunc = three.GreaterDepth;
          edgesGroup.add(three.LineSegments(obsGeo, obsMat));
        }
      }
    }

    // 4. Laser cut lines (cyan dashed / distinct CAD color, single draw call)
    if (laserCutCoords.isNotEmpty) {
      final laserGeo = three.BufferGeometry();
      laserGeo.setAttribute(three.Attribute.position, three.Float32BufferAttribute.fromList(laserCutCoords, 3));
      final laserMat = three.LineBasicMaterial.fromMap({
        'color': 0x0284C7, // Vivid cyan-blue laser kerf
        'linewidth': 1.5,
        'depthTest': true,
        'depthWrite': false,
      });
      edgesGroup.add(three.LineSegments(laserGeo, laserMat));
    }

    rootGroup.add(edgesGroup);
    return rootGroup;
  }

  /// Appends line segment with in-plane offset strokes for visible line thickness on all GPUs.
  static void _appendLineWithWidth(
    CadPoint3D p1,
    CadPoint3D p2,
    CadPoint3D pivot,
    CadPoint3D normal,
    double width,
    List<double> out, {
    double pxInWorld = 1.0,
  }) {
    out.addAll([p1.x - pivot.x, p1.y - pivot.y, p1.z - pivot.z, p2.x - pivot.x, p2.y - pivot.y, p2.z - pivot.z]);
    if (width > 1.4) {
      final dx = p2.x - p1.x;
      final dy = p2.y - p1.y;
      final dz = p2.z - p1.z;
      // In-plane vector perpendicular to edge: T = (p2 - p1) x normal
      var tx = dy * normal.z - dz * normal.y;
      var ty = dz * normal.x - dx * normal.z;
      var tz = dx * normal.y - dy * normal.x;
      final tLen = math.sqrt(tx * tx + ty * ty + tz * tz);
      if (tLen > 0.001) {
        tx /= tLen;
        ty /= tLen;
        tz /= tLen;
        final step = math.max(0.15, pxInWorld * 0.35) * (width / 2.0);
        out.addAll([
          p1.x + tx * step - pivot.x,
          p1.y + ty * step - pivot.y,
          p1.z + tz * step - pivot.z,
          p2.x + tx * step - pivot.x,
          p2.y + ty * step - pivot.y,
          p2.z + tz * step - pivot.z,
          p1.x - tx * step - pivot.x,
          p1.y - ty * step - pivot.y,
          p1.z - tz * step - pivot.z,
          p2.x - tx * step - pivot.x,
          p2.y - ty * step - pivot.y,
          p2.z - tz * step - pivot.z,
        ]);
        if (width > 3.0) {
          final step2 = step * 2.0;
          out.addAll([
            p1.x + tx * step2 - pivot.x,
            p1.y + ty * step2 - pivot.y,
            p1.z + tz * step2 - pivot.z,
            p2.x + tx * step2 - pivot.x,
            p2.y + ty * step2 - pivot.y,
            p2.z + tz * step2 - pivot.z,
            p1.x - tx * step2 - pivot.x,
            p1.y - ty * step2 - pivot.y,
            p1.z - tz * step2 - pivot.z,
            p2.x - tx * step2 - pivot.x,
            p2.y - ty * step2 - pivot.y,
            p2.z - tz * step2 - pivot.z,
          ]);
        }
      }
    }
  }

  /// Decomposes segment [p1, p2] into ISO/ANSI CAD phantom line dashes (long dash, dot, long dash).
  static void _appendPhantomDashes(CadPoint3D p1, CadPoint3D p2, CadPoint3D pivot, List<double> out) {
    final dx = p2.x - p1.x;
    final dy = p2.y - p1.y;
    final dz = p2.z - p1.z;
    final len = math.sqrt(dx * dx + dy * dy + dz * dz);
    if (len < 0.5) return;

    final ux = dx / len;
    final uy = dy / len;
    final uz = dz / len;

    // ISO/ANSI CAD Phantom line pattern: Long dash 4.0mm, space 1.8mm, dot 1.2mm, space 1.8mm
    const d1 = 4.0;
    const s1 = 1.8;
    const d2 = 1.2;
    const s2 = 1.8;

    double s = 0.0;
    while (s < len) {
      final e1 = math.min(s + d1, len);
      out.addAll([
        p1.x + ux * s - pivot.x,
        p1.y + uy * s - pivot.y,
        p1.z + uz * s - pivot.z,
        p1.x + ux * e1 - pivot.x,
        p1.y + uy * e1 - pivot.y,
        p1.z + uz * e1 - pivot.z,
      ]);
      s += d1 + s1;
      if (s >= len) break;

      final e2 = math.min(s + d2, len);
      out.addAll([
        p1.x + ux * s - pivot.x,
        p1.y + uy * s - pivot.y,
        p1.z + uz * s - pivot.z,
        p1.x + ux * e2 - pivot.x,
        p1.y + uy * e2 - pivot.y,
        p1.z + uz * e2 - pivot.z,
      ]);
      s += d2 + s2;
    }
  }

  /// Generates a thick, MSAA-antialiased quad ribbon in the plane of the face.
  static void _appendRibbonQuad(
    CadPoint3D p1,
    CadPoint3D p2,
    CadPoint3D pivot,
    CadPoint3D normal,
    double widthMm,
    List<double> outPositions,
    List<double> outNormals, {
    double pxInWorld = 1.0,
  }) {
    final dx = p2.x - p1.x;
    final dy = p2.y - p1.y;
    final dz = p2.z - p1.z;
    final len = math.sqrt(dx * dx + dy * dy + dz * dz);
    if (len < 1e-4) return;

    final dirX = dx / len;
    final dirY = dy / len;
    final dirZ = dz / len;

    // In-plane perpendicular vector: T = Dir x Normal
    var tx = dirY * normal.z - dirZ * normal.y;
    var ty = dirZ * normal.x - dirX * normal.z;
    var tz = dirX * normal.y - dirY * normal.x;
    var tLen = math.sqrt(tx * tx + ty * ty + tz * tz);
    if (tLen < 1e-4) {
      final ax = normal.z.abs() < 0.9 ? 0.0 : 1.0;
      final ay = 0.0;
      final az = normal.z.abs() < 0.9 ? 1.0 : 0.0;
      tx = dirY * az - dirZ * ay;
      ty = dirZ * ax - dirX * az;
      tz = dirX * ay - dirY * ax;
      tLen = math.sqrt(tx * tx + ty * ty + tz * tz);
      if (tLen < 1e-4) return;
    }
    tx /= tLen;
    ty /= tLen;
    tz /= tLen;

    final halfW = widthMm / 2.0;
    // Lift slightly above face to prevent z-fighting with the underlying planar face
    final offsetDist = math.max(0.08, pxInWorld * 0.12);
    final offX = normal.x * offsetDist;
    final offY = normal.y * offsetDist;
    final offZ = normal.z * offsetDist;

    final p1x = p1.x - pivot.x + offX;
    final p1y = p1.y - pivot.y + offY;
    final p1z = p1.z - pivot.z + offZ;

    final p2x = p2.x - pivot.x + offX;
    final p2y = p2.y - pivot.y + offY;
    final p2z = p2.z - pivot.z + offZ;

    final v0x = p1x - tx * halfW;
    final v0y = p1y - ty * halfW;
    final v0z = p1z - tz * halfW;

    final v1x = p1x + tx * halfW;
    final v1y = p1y + ty * halfW;
    final v1z = p1z + tz * halfW;

    final v2x = p2x + tx * halfW;
    final v2y = p2y + ty * halfW;
    final v2z = p2z + tz * halfW;

    final v3x = p2x - tx * halfW;
    final v3y = p2y - ty * halfW;
    final v3z = p2z - tz * halfW;

    // Triangle 1: v0, v1, v2
    outPositions.addAll([v0x, v0y, v0z, v1x, v1y, v1z, v2x, v2y, v2z]);
    outNormals.addAll([normal.x, normal.y, normal.z, normal.x, normal.y, normal.z, normal.x, normal.y, normal.z]);

    // Triangle 2: v0, v2, v3
    outPositions.addAll([v0x, v0y, v0z, v2x, v2y, v2z, v3x, v3y, v3z]);
    outNormals.addAll([normal.x, normal.y, normal.z, normal.x, normal.y, normal.z, normal.x, normal.y, normal.z]);
  }

  /// Generates antialiased thick phantom dashes using ribbon quads.
  static void _appendPhantomDashRibbons(
    CadPoint3D p1,
    CadPoint3D p2,
    CadPoint3D pivot,
    CadPoint3D normal,
    double widthMm,
    List<double> outPositions,
    List<double> outNormals, {
    double pxInWorld = 1.0,
  }) {
    final dx = p2.x - p1.x;
    final dy = p2.y - p1.y;
    final dz = p2.z - p1.z;
    final len = math.sqrt(dx * dx + dy * dy + dz * dz);
    if (len < 0.5) return;

    final ux = dx / len;
    final uy = dy / len;
    final uz = dz / len;

    const d1 = 4.0;
    const s1 = 1.8;
    const d2 = 1.2;
    const s2 = 1.8;
    const cycle = d1 + s1 + d2 + s2;

    double cur = 0.0;
    while (cur < len) {
      final e1 = math.min(len, cur + d1);
      if (e1 > cur) {
        final a = CadPoint3D(p1.x + ux * cur, p1.y + uy * cur, p1.z + uz * cur);
        final b = CadPoint3D(p1.x + ux * e1, p1.y + uy * e1, p1.z + uz * e1);
        _appendRibbonQuad(a, b, pivot, normal, widthMm, outPositions, outNormals, pxInWorld: pxInWorld);
      }
      final dStart = cur + d1 + s1;
      final dEnd = math.min(len, dStart + d2);
      if (dStart < len && dEnd > dStart) {
        final a = CadPoint3D(p1.x + ux * dStart, p1.y + uy * dStart, p1.z + uz * dStart);
        final b = CadPoint3D(p1.x + ux * dEnd, p1.y + uy * dEnd, p1.z + uz * dEnd);
        _appendRibbonQuad(a, b, pivot, normal, widthMm, outPositions, outNormals, pxInWorld: pxInWorld);
      }
      cur += cycle;
    }
  }

  /// Triangulates a polygon with cutout holes and appends its vertices directly into the batched arrays.
  static void _triangulateHolePolygon(
    CadFoldedPolygon3D poly, {
    required CadPoint3D pivot,
    required List<double> outPositions,
    required List<double> outNormals,
    required List<double> outColors,
    required double colorR,
    required double colorG,
    required double colorB,
  }) {
    final n = poly.normal;
    final lenN = math.sqrt(n.x * n.x + n.y * n.y + n.z * n.z);
    final nz = lenN > 1e-6 ? CadPoint3D(n.x / lenN, n.y / lenN, n.z / lenN) : const CadPoint3D(0, 0, 1);

    // Orthonormal tangent basis (u, v) on polygon plane
    final up = nz.z.abs() < 0.9 ? const CadPoint3D(0, 0, 1) : const CadPoint3D(1, 0, 0);

    final ux = up.y * nz.z - up.z * nz.y;
    final uy = up.z * nz.x - up.x * nz.z;
    final uz = up.x * nz.y - up.y * nz.x;
    final lenU = math.sqrt(ux * ux + uy * uy + uz * uz);
    if (lenU < 1e-6) return;
    final u = CadPoint3D(ux / lenU, uy / lenU, uz / lenU);

    final vx = nz.y * u.z - nz.z * u.y;
    final vy = nz.z * u.x - nz.x * u.z;
    final vz = nz.x * u.y - nz.y * u.x;
    final v = CadPoint3D(vx, vy, vz);

    final origin = poly.vertices[0];

    (double, double) projectTo2D(CadPoint3D pt) {
      final dx = pt.x - origin.x;
      final dy = pt.y - origin.y;
      final dz = pt.z - origin.z;
      return (dx * u.x + dy * u.y + dz * u.z, dx * v.x + dy * v.y + dz * v.z);
    }

    // Outer contour
    final shape = three.Shape();
    final p0 = projectTo2D(poly.vertices[0]);
    shape.moveTo(p0.$1, p0.$2);
    for (int i = 1; i < poly.vertices.length; i++) {
      final pi = projectTo2D(poly.vertices[i]);
      shape.lineTo(pi.$1, pi.$2);
    }
    shape.closePath();

    // Inner cutout holes (slots, perforations, punch openings)
    for (final hole in poly.holes) {
      if (hole.length < 3) continue;
      final holePath = three.Path();
      final hp0 = projectTo2D(hole[0]);
      holePath.moveTo(hp0.$1, hp0.$2);
      for (int i = 1; i < hole.length; i++) {
        final hpi = projectTo2D(hole[i]);
        holePath.lineTo(hpi.$1, hpi.$2);
      }
      holePath.closePath();
      shape.holes.add(holePath);
    }

    try {
      final geometry = three_geo.ShapeGeometry([shape]);
      final posAttr = geometry.getAttribute(three.Attribute.position);
      final posArray = posAttr.array;
      final indexArray = geometry.index?.array;

      final ox = origin.x - pivot.x;
      final oy = origin.y - pivot.y;
      final oz = origin.z - pivot.z;

      if (indexArray != null) {
        for (int i = 0; i < indexArray.length; i++) {
          final idx = indexArray[i].toInt();
          final lx = posArray[idx * 3];
          final ly = posArray[idx * 3 + 1];

          // Project back from 2D plane basis to 3D world space
          final wx = ox + lx * u.x + ly * v.x;
          final wy = oy + lx * u.y + ly * v.y;
          final wz = oz + lx * u.z + ly * v.z;

          outPositions.addAll([wx, wy, wz]);
          outNormals.addAll([nz.x, nz.y, nz.z]);
          outColors.addAll([colorR, colorG, colorB]);
        }
      } else {
        for (int i = 0; i < posArray.length; i += 3) {
          final lx = posArray[i];
          final ly = posArray[i + 1];

          final wx = ox + lx * u.x + ly * v.x;
          final wy = oy + lx * u.y + ly * v.y;
          final wz = oz + lx * u.z + ly * v.z;

          outPositions.addAll([wx, wy, wz]);
          outNormals.addAll([nz.x, nz.y, nz.z]);
          outColors.addAll([colorR, colorG, colorB]);
        }
      }
    } catch (_) {
      // Gracefully continue if non-manifold hole cannot be triangulated
    }
  }
}
