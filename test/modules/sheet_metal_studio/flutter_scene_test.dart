import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:trufold_studio/sheet_metal_studio/engine/kinematic_fold_engine.dart';
import 'package:trufold_studio/sheet_metal_studio/models/dsf_document.dart';
import 'package:trufold_studio/sheet_metal_studio/models/cad_primitives.dart';
import 'package:trufold_studio/sheet_metal_studio/models/fold_bend_line.dart';
import 'package:trufold_studio/sheet_metal_studio/views/widgets/canvas_2d/controllers/vector_cad_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Flutter Scene 0.24.0 Integration & Procedural Mesh Tests', () {
    test('Constructs Scene, PerspectiveCamera, and checks camera properties', () {
      final camera = PerspectiveCamera(
        position: vm.Vector3(0, 50, 150),
        target: vm.Vector3(0, 0, 0),
      );
      expect(camera, isNotNull);
      expect(camera.position.z, equals(150.0));
      expect(camera.target.y, equals(0.0));
    });

    test('Procedural CAD Mesh generation from KinematicFoldEngine using GeometryBuilder', () {
      // 1. Synthesize CAD sheet metal part via VectorCadController
      final controller = VectorCadController();
      final doc = controller.toDsfDocument();

      final foldedMesh = KinematicFoldEngine.foldDocument(doc, foldProgress: 1.0);
      expect(foldedMesh.polygons, isNotEmpty);

      // 2. GeometryBuilder dynamically constructs triangles directly from foldedMesh
      final builder = GeometryBuilder();
      int trianglesCount = 0;

      for (final poly in foldedMesh.polygons) {
        if (poly.vertices.length < 3) continue;

        // Triangulate n-gon into triangle fan
        final v0 = poly.vertices[0];
        for (int i = 1; i < poly.vertices.length - 1; i++) {
          final v1 = poly.vertices[i];
          final v2 = poly.vertices[i + 1];

          final i0 = builder.addVertex(vm.Vector3(v0.x, v0.y, v0.z));
          final i1 = builder.addVertex(vm.Vector3(v1.x, v1.y, v1.z));
          final i2 = builder.addVertex(vm.Vector3(v2.x, v2.y, v2.z));

          builder.addTriangle(i0, i1, i2);
          trianglesCount++;
        }
      }

      expect(builder.vertexCount, greaterThan(0));
      expect(builder.triangleCount, equals(trianglesCount));

      // 3. Test packVertices (pure CPU interleaved byte packing, verified without GPU context)
      final packedBytes = builder.packVertices();
      expect(packedBytes, isNotEmpty);
      expect(packedBytes.length, greaterThan(0));
    });
  });
}
