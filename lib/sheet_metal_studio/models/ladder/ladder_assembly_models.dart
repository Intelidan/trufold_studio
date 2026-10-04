import '../cad_part.dart';
import '../cad_primitives.dart';
import '../cms/cms_physical_port.dart';
import '../../engine/kinematic_fold_engine.dart';
import 'ladder_assembly_parameters.dart';

/// Single spatial rung instance in the assembled cable ladder.
class LadderRungInstance {
  final int index;
  final double stationX;
  final CadPoint3D center3D;
  final double cutLength;
  final double orientationAngleRad;
  final LadderRungJointMethod jointMethod;

  const LadderRungInstance({
    required this.index,
    required this.stationX,
    required this.center3D,
    required this.cutLength,
    this.orientationAngleRad = 0.0,
    required this.jointMethod,
  });
}

/// Single mechanical / welded joint interface between a rung end and a side rail.
class LadderJointInstance {
  final int rungIndex;
  final String railSide; // 'left' or 'right'
  final double stationX;
  final CadPoint3D weldCenter3D;
  final CadPoint2D? slotCenter2D;
  final bool hasOpening;
  final double outsideProjection;

  const LadderJointInstance({
    required this.rungIndex,
    required this.railSide,
    required this.stationX,
    required this.weldCenter3D,
    this.slotCenter2D,
    required this.hasOpening,
    this.outsideProjection = 0.0,
  });
}

/// Detailed Hardware and Bill of Materials (BOM) Takeoff.
class LadderHardwareBOM {
  final int rungCount;
  final int leftRailCount;
  final int rightRailCount;
  final int passThroughSlotCount;
  final int weldJointCount;
  final double totalWeldLengthMm;
  final int spliceCouplerCount;
  final int couplerBoltCount; // M6x16 SS316
  final int couplerNutCount;  // M6 SS316
  final int couplerWasherCount; // M6 SS316 Star
  final int holdDownClampCount;
  final int holdDownBoltCount; // M8x30 SS316
  final int coverClampCount;
  final double totalSteelWeightKg;

  const LadderHardwareBOM({
    required this.rungCount,
    this.leftRailCount = 1,
    this.rightRailCount = 1,
    required this.passThroughSlotCount,
    required this.weldJointCount,
    required this.totalWeldLengthMm,
    this.spliceCouplerCount = 2,
    this.couplerBoltCount = 8,
    this.couplerNutCount = 8,
    this.couplerWasherCount = 8,
    this.holdDownClampCount = 2,
    this.holdDownBoltCount = 2,
    this.coverClampCount = 0,
    this.totalSteelWeightKg = 0.0,
  });
}

/// The complete multi-body cable ladder assembly model.
/// Contains constituent flat blanks for CNC cutting/nesting,
/// 3D kinematic assembly meshes for viewports, and hardware BOM takeoff.
class DsfLadderAssembly {
  final String id;
  final String productName;
  final LadderAssemblyParameters parameters;
  
  // Constituent manufacturable flat blanks for CAM / Turret Punching / Nesting
  final CadPart leftRailBlank;
  final CadPart rightRailBlank;
  final CadPart rungBlank;
  final CadPart? coverBlank;

  // Spatial 3D and joint topologies
  final List<LadderRungInstance> rungs;
  final List<LadderJointInstance> joints;
  final List<CmsPhysicalPort> splicePorts;

  // 3D Assembly Meshes for shaded isometric rendering
  final FoldedMeshResult assembledMesh3D;
  final FoldedMeshResult? coverMesh3D;

  // Fasteners and BOM takeoff
  final LadderHardwareBOM hardwareBOM;

  const DsfLadderAssembly({
    required this.id,
    required this.productName,
    required this.parameters,
    required this.leftRailBlank,
    required this.rightRailBlank,
    required this.rungBlank,
    this.coverBlank,
    required this.rungs,
    required this.joints,
    this.splicePorts = const [],
    required this.assembledMesh3D,
    this.coverMesh3D,
    required this.hardwareBOM,
  });
}
