// Converts parametric steps, geometry options, and layout vectors to a compact, portable JSON data payload.

import 'dart:convert';
import 'package:vector_math/vector_math.dart' as vm;
import '../cad_parameter_engine/cad_models.dart';

class CADSerializer {
  static String serializeHistory(List<CADHistoryItem> history) {
    return jsonEncode(
      history
          .map(
            (item) => {
              'id': item.id,
              'name': item.name,
              'timestamp': item.timestamp.toIso8601String(),
              'isActive': item.isActive,
              'featureType': item.featureType.name,
              'depth': item.modificationDepth,
              if (item.referencePlane != null) 'plane': _encP(item.referencePlane!),
            },
          )
          .toList(),
    );
  }

  static List<CADHistoryItem> deserializeHistory(String jsonStr) {
    if (jsonStr.isEmpty) return [];
    return (jsonDecode(jsonStr) as List)
        .map(
          (d) => CADHistoryItem(
            id: d['id'],
            name: d['name'],
            timestamp: DateTime.parse(d['timestamp']),
            isActive: d['isActive'],
            featureType: FeatureType.values.byName(d['featureType']),
            modificationDepth: d['depth'].toDouble(),
            referencePlane: d.containsKey('plane') ? _decP(d['plane']) : null,
          ),
        )
        .toList();
  }

  static Map<String, dynamic> _encP(CADSketchPlane p) => {
    'id': p.id,
    'ori': [p.origin.x, p.origin.y, p.origin.z],
    'nrm': [p.normal.x, p.normal.y, p.normal.z],
    'up': [p.up.x, p.up.y, p.up.z],
  };
  static CADSketchPlane _decP(Map<String, dynamic> j) => CADSketchPlane(
    id: j['id'],
    origin: vm.Vector3(j['ori'][0], j['ori'][1], j['ori'][2]),
    normal: vm.Vector3(j['nrm'][0], j['nrm'][1], j['nrm'][2]),
    up: vm.Vector3(j['up'][0], j['up'][1], j['up'][2]),
  );
}
