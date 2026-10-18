import 'dart:math' as math;
import 'package:vector_math/vector_math.dart';
import '../../models/assembly_part.dart';

/// 3D Hole Center snap point representation for X-ray hover-snapping
class HoleSnapSpot {
  final String id;
  final String partId;
  final Vector3 worldCenter;
  final double diameterMm;

  const HoleSnapSpot({
    required this.id,
    required this.partId,
    required this.worldCenter,
    required this.diameterMm,
  });
}

class CadImprintedBorderEdge2D {
  final String id;
  final Vector2 start2D;
  final Vector2 end2D;
  final bool isFixedReference;

  const CadImprintedBorderEdge2D({
    required this.id,
    required this.start2D,
    required this.end2D,
    this.isFixedReference = true,
  });

  Vector2 get midpoint2D => (start2D + end2D) * 0.5;
  Vector2 get directionUnit {
    final d = end2D - start2D;
    final len = d.length;
    return len > 1e-5 ? d / len : Vector2(1.0, 0.0);
  }
}

class CadImprintedHole2D {
  final String id;
  final Vector2 center2D;
  final double diameterMm;

  const CadImprintedHole2D({
    required this.id,
    required this.center2D,
    required this.diameterMm,
  });
}

class CadPlanarFaceBRep {
  final String faceId;
  final String hostPartId;
  final Vector3 originWorld;
  final Vector3 uAxisWorld;
  final Vector3 vAxisWorld;
  final Vector3 normalWorld;
  final List<CadImprintedBorderEdge2D> outerBorderEdges2D;
  final List<CadImprintedHole2D> holes2D;

  const CadPlanarFaceBRep({
    required this.faceId,
    required this.hostPartId,
    required this.originWorld,
    required this.uAxisWorld,
    required this.vAxisWorld,
    required this.normalWorld,
    required this.outerBorderEdges2D,
    required this.holes2D,
  });

  Vector2 worldToSketch2D(Vector3 worldPt) {
    final Vector3 rel = worldPt - originWorld;
    return Vector2(rel.dot(uAxisWorld), rel.dot(vAxisWorld));
  }

  Vector3 sketch2DToWorld(Vector2 pt2D, {double normalOffsetMm = 0.0}) {
    return originWorld +
        (uAxisWorld * pt2D.x) +
        (vAxisWorld * pt2D.y) +
        (normalWorld * normalOffsetMm);
  }

  /// Extracts the exact rectangular/polygonal outer border edges and hole centers
  /// of the host AssemblyPart face so Sketch Mode can dimension directly to part borders (SS5).
  static CadPlanarFaceBRep extractFromPartFace({
    required AssemblyPart part,
    required Vector3 planeOriginWorld,
    required Vector3 planeNormalWorld,
    required Vector3 planeUAxisWorld,
    required Vector3 planeVAxisWorld,
  }) {
    final List<CadImprintedBorderEdge2D> borders = <CadImprintedBorderEdge2D>[];
    final List<CadImprintedHole2D> holes = <CadImprintedHole2D>[];

    Vector2 to2D(Vector3 w) {
      final rel = w - planeOriginWorld;
      return Vector2(rel.dot(planeUAxisWorld), rel.dot(planeVAxisWorld));
    }

    // Project part's oriented bounding box / topological coplanar boundary vertices onto (u, v)
    final List<Vector3> cornerPts = part.getWorldCorners();
    if (cornerPts.isNotEmpty) {
      double minU = double.infinity, maxU = -double.infinity;
      double minV = double.infinity, maxV = -double.infinity;
      for (final c in cornerPts) {
        final p2 = to2D(c);
        minU = math.min(minU, p2.x);
        maxU = math.max(maxU, p2.x);
        minV = math.min(minV, p2.y);
        maxV = math.max(maxV, p2.y);
      }
      final b0 = Vector2(minU, minV);
      final b1 = Vector2(maxU, minV);
      final b2 = Vector2(maxU, maxV);
      final b3 = Vector2(minU, maxV);

      borders.addAll([
        CadImprintedBorderEdge2D(id: 'border_bottom_${part.id}', start2D: b0, end2D: b1),
        CadImprintedBorderEdge2D(id: 'border_right_${part.id}', start2D: b1, end2D: b2),
        CadImprintedBorderEdge2D(id: 'border_top_${part.id}', start2D: b2, end2D: b3),
        CadImprintedBorderEdge2D(id: 'border_left_${part.id}', start2D: b3, end2D: b0),
      ]);
    }

    // Imprint existing hole centers on or parallel to this face
    for (int i = 0; i < part.holeCentersWorld.length; i++) {
      final Vector3 hc = part.holeCentersWorld[i];
      holes.add(
        CadImprintedHole2D(
          id: 'imprinted_hole_${part.id}_$i',
          center2D: to2D(hc),
          diameterMm: part.holeDiametersMm.length > i ? part.holeDiametersMm[i] : 12.0,
        ),
      );
    }

    return CadPlanarFaceBRep(
      faceId: 'face_${part.id}',
      hostPartId: part.id,
      originWorld: planeOriginWorld,
      uAxisWorld: planeUAxisWorld.normalized(),
      vAxisWorld: planeVAxisWorld.normalized(),
      normalWorld: planeNormalWorld.normalized(),
      outerBorderEdges2D: borders,
      holes2D: holes,
    );
  }
}
