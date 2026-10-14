// Processes raw high-precision vertex float tables to compile compliant industrial ASCII .STL files for 3D printing.

import 'dart:typed_data';

import 'package:vector_math/vector_math.dart' as vm;

class CADSTLExporter {
  static String exportToASCIISTL({required Float32List vertices, required Uint16List indices, required String name, int stride = 6}) {
    final sb = StringBuffer()..writeln("solid ${name.replaceAll(' ', '_')}");
    for (int i = 0; i < indices.length; i += 3) {
      int i0 = indices[i] * stride;
      int i1 = indices[i + 1] * stride;
      int i2 = indices[i + 2] * stride;
      final v0 = vm.Vector3(vertices[i0], vertices[i0 + 1], vertices[i0 + 2]);
      final v1 = vm.Vector3(vertices[i1], vertices[i1 + 1], vertices[i1 + 2]);
      final v2 = vm.Vector3(vertices[i2], vertices[i2 + 1], vertices[i2 + 2]);
      vm.Vector3 n = (v1 - v0).cross(v2 - v0).normalized();
      sb.writeln("  facet normal ${n.x.toStringAsExponential(6)} ${n.y.toStringAsExponential(6)} ${n.z.toStringAsExponential(6)}");
      sb.writeln("    outer loop");
      sb.writeln("      vertex ${v0.x.toStringAsExponential(6)} ${v0.y.toStringAsExponential(6)} ${v0.z.toStringAsExponential(6)}");
      sb.writeln("      vertex ${v1.x.toStringAsExponential(6)} ${v1.y.toStringAsExponential(6)} ${v1.z.toStringAsExponential(6)}");
      sb.writeln("      vertex ${v2.x.toStringAsExponential(6)} ${v2.y.toStringAsExponential(6)} ${v2.z.toStringAsExponential(6)}");
      sb.writeln("    endloop");
      sb.writeln("  endfacet");
    }
    return (sb..writeln("endsolid $name")).toString();
  }
}
