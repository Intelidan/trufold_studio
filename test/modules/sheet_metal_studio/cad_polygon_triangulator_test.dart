import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_scene/scene.dart';
import 'package:trufold_studio/sheet_metal_studio/engine/cad_polygon_triangulator.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('CadPolygonTriangulator correctly triangulates simple 2D polygon with hole', () {
    // 100x100 square with 40x40 square hole in the center
    final outer = [
      0.0, 0.0,
      100.0, 0.0,
      100.0, 100.0,
      0.0, 100.0,
    ];
    final hole = [
      30.0, 30.0,
      70.0, 30.0,
      70.0, 70.0,
      30.0, 70.0,
    ];

    final flatCoords = [...outer, ...hole];
    final holeIndices = [4]; // hole starts at vertex index 4

    final triangles = CadPolygonTriangulator.triangulate(flatCoords, holeIndices);

    expect(triangles.length % 3, 0);
    expect(triangles.isNotEmpty, true);

    // Calculate total area of triangles
    double totalArea = 0.0;
    for (int i = 0; i < triangles.length; i += 3) {
      final i0 = triangles[i];
      final i1 = triangles[i + 1];
      final i2 = triangles[i + 2];

      final x0 = flatCoords[i0 * 2];
      final y0 = flatCoords[i0 * 2 + 1];
      final x1 = flatCoords[i1 * 2];
      final y1 = flatCoords[i1 * 2 + 1];
      final x2 = flatCoords[i2 * 2];
      final y2 = flatCoords[i2 * 2 + 1];

      // Cross product area
      final triArea = 0.5 * ((x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)).abs();
      totalArea += triArea;
    }

    // Outer area = 10000, Hole area = 1600 -> Expected area = 8400
    expect(totalArea, closeTo(8400.0, 0.001));
  });

  test('CadPolygonTriangulator.triangulateToBuilder triangulates 3D face with cutout hole', () {
    final builder = GeometryBuilder(deduplicate: true);

    final outer3D = [
      const CadPoint3D(0, 0, 0),
      const CadPoint3D(100, 0, 0),
      const CadPoint3D(100, 100, 0),
      const CadPoint3D(0, 100, 0),
    ];
    final hole3D = [
      const CadPoint3D(30, 30, 0),
      const CadPoint3D(70, 30, 0),
      const CadPoint3D(70, 70, 0),
      const CadPoint3D(30, 70, 0),
    ];

    CadPolygonTriangulator.triangulateToBuilder(
      outerVertices: outer3D,
      holes: [hole3D],
      normal: const CadPoint3D(0, 0, 1),
      pivot: const CadPoint3D(50, 50, 0),
      builder: builder,
    );

    expect(builder.triangleCount, greaterThan(0));
    expect(builder.vertexCount, greaterThan(0));
  });
}
