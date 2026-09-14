import "package:trufold_studio/sheet_metal_studio/engine/topological_zone_morpher.dart";

void main() {
  final tee = TopologicalZoneMorpher.createBaselineTee(width: 100, height: 50, branchWidth: 100);
  for (final b in tee.bends) {
    print("${b.id}: p1=${b.p1}, p2=${b.p2}");
  }
}
