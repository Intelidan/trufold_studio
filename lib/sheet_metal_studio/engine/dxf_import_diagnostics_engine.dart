// =============================================================================
// dxf_import_diagnostics_engine.dart
//
// DXF Import Diagnostics & Non-Destructive Geometry Healing per Step 9 (#22).
// Inspects incoming DXF entities for profile closure, slot shapes, bend lines,
// duplicate elements, zero-length segments, and micro-gaps before importing.
// =============================================================================

import 'dart:math' as math;
import '../models/cad_primitives.dart';
import 'dxf_mini_parser.dart';

class DxfDiagnosticErrorLocation {
  final CadPoint2D point;
  final String issueType; // 'duplicate', 'zeroLength', 'microGap', 'unclosedLoop'
  final String description;

  const DxfDiagnosticErrorLocation({
    required this.point,
    required this.issueType,
    required this.description,
  });
}

class DxfDiagnosticsReport {
  final int totalEntities;
  final Map<String, int> entityCountsByType;
  final int closedProfilesCount;
  final int openProfilesCount;
  final int slotProfilesCount;
  final int bendCandidatesCount;
  final int duplicateEntitiesCount;
  final int zeroLengthEntitiesCount;
  final int geometryGapsCount;
  final List<String> warnings;
  final Set<String> layersFound;
  final List<DxfDiagnosticErrorLocation> errorLocations;
  final DxfParsedData? parsedData;

  const DxfDiagnosticsReport({
    required this.totalEntities,
    required this.entityCountsByType,
    required this.closedProfilesCount,
    required this.openProfilesCount,
    required this.slotProfilesCount,
    required this.bendCandidatesCount,
    required this.duplicateEntitiesCount,
    required this.zeroLengthEntitiesCount,
    required this.geometryGapsCount,
    required this.warnings,
    required this.layersFound,
    this.errorLocations = const [],
    this.parsedData,
  });

  bool get hasIssues =>
      duplicateEntitiesCount > 0 ||
      zeroLengthEntitiesCount > 0 ||
      geometryGapsCount > 0 ||
      openProfilesCount > 0;
}

class DxfHealingResult {
  final DxfParsedData healedData;
  final int duplicatesRemoved;
  final int zeroLengthRemoved;
  final int gapsHealed;

  const DxfHealingResult({
    required this.healedData,
    required this.duplicatesRemoved,
    required this.zeroLengthRemoved,
    required this.gapsHealed,
  });
}

class _DiagSegment {
  final CadPoint2D start;
  final CadPoint2D end;
  final List<CadPoint2D> points;

  _DiagSegment({required this.start, required this.end, required this.points});
}

class DxfImportDiagnosticsEngine {
  /// Analyzes parsed DXF entities and produces a thorough diagnostics report
  static DxfDiagnosticsReport analyze(DxfParsedData parsed) {
    final typeCounts = <String, int>{};
    final layers = Set<String>.from(parsed.layers);

    for (final e in parsed.entities) {
      final name = e.runtimeType.toString().replaceAll('DxfRaw', '').toUpperCase();
      typeCounts[name] = (typeCounts[name] ?? 0) + 1;
    }

    final lines = parsed.getEntitiesOfType<DxfRawLine>();
    final polylines = parsed.getEntitiesOfType<DxfRawPolyline>();
    final circles = parsed.getEntitiesOfType<DxfRawCircle>();
    final arcs = parsed.getEntitiesOfType<DxfRawArc>();

    final errorLocations = <DxfDiagnosticErrorLocation>[];

    // 1. Duplicate Entities Detection (Lines, Arcs & Polylines)
    int duplicates = 0;
    for (int i = 0; i < lines.length; i++) {
      for (int j = i + 1; j < lines.length; j++) {
        if (_isDuplicateLine(lines[i], lines[j]) ||
            _isCollinearSubsegment(lines[i].p1, lines[i].p2, lines[j].p1, lines[j].p2) ||
            _isCollinearSubsegment(lines[j].p1, lines[j].p2, lines[i].p1, lines[i].p2)) {
          duplicates++;
          errorLocations.add(
            DxfDiagnosticErrorLocation(
              point: CadPoint2D(
                (lines[i].p1.x + lines[i].p2.x) / 2.0,
                (lines[i].p1.y + lines[i].p2.y) / 2.0,
              ),
              issueType: 'duplicate',
              description: 'Duplicate or redundant collinear line segment',
            ),
          );
        }
      }
    }
    for (int i = 0; i < arcs.length; i++) {
      for (int j = i + 1; j < arcs.length; j++) {
        if (_isDuplicateArc(arcs[i], arcs[j])) {
          duplicates++;
          errorLocations.add(
            DxfDiagnosticErrorLocation(
              point: arcs[i].center,
              issueType: 'duplicate',
              description: 'Duplicate arc entity',
            ),
          );
        }
      }
    }
    for (int i = 0; i < polylines.length; i++) {
      for (int j = i + 1; j < polylines.length; j++) {
        if (_isDuplicatePolyline(polylines[i], polylines[j])) {
          duplicates++;
          errorLocations.add(
            DxfDiagnosticErrorLocation(
              point: polylines[i].vertices.isNotEmpty
                  ? polylines[i].vertices.first
                  : const CadPoint2D(0, 0),
              issueType: 'duplicate',
              description: 'Duplicate polyline entity',
            ),
          );
        }
      }
    }

    // 2. Zero-Length Entities Detection
    int zeroLength = 0;
    for (final l in lines) {
      if (l.length < 0.01) {
        zeroLength++;
        errorLocations.add(
          DxfDiagnosticErrorLocation(
            point: l.p1,
            issueType: 'zeroLength',
            description: 'Zero-length segment (< 0.01 mm)',
          ),
        );
      }
    }

    // 3. Bend Candidates
    int bendCandidates = 0;
    for (final l in lines) {
      final layer = l.layer.toLowerCase();
      if (layer.contains('bend') ||
          layer.contains('fold') ||
          layer.contains('center') ||
          l.colorIndex == 4 || // Cyan (BEND_UP)
          l.colorIndex == 2) { // Yellow (BEND_DOWN)
        bendCandidates++;
      }
    }

    // 4. Topological Connected Loops & Profiles Analysis
    int closedProfiles = 0;
    int openProfiles = 0;
    int slotProfiles = 0;

    // Circles are always closed profiles
    closedProfiles += circles.length;

    // Check closed polylines directly
    for (final poly in polylines) {
      if (poly.isClosed ||
          (poly.vertices.length >= 3 &&
              poly.vertices.first.distanceTo(poly.vertices.last) < 0.5)) {
        closedProfiles++;
        if (_isSlotLikeLoop(poly.vertices)) {
          slotProfiles++;
        }
      }
    }

    // Build segments from boundary lines, arcs, and open polylines
    final boundaryLines = lines.where((l) {
      final layer = l.layer.toLowerCase();
      return !layer.contains('bend') &&
          !layer.contains('fold') &&
          !layer.contains('center') &&
          l.colorIndex != 4 &&
          l.colorIndex != 2;
    }).toList();

    final segments = <_DiagSegment>[];
    for (final l in boundaryLines) {
      segments.add(_DiagSegment(start: l.p1, end: l.p2, points: [l.p1, l.p2]));
    }
    for (final a in arcs) {
      final s = _arcStart(a);
      final e = _arcEnd(a);
      segments.add(_DiagSegment(start: s, end: e, points: [s, e]));
    }
    for (final poly in polylines) {
      if (!poly.isClosed && poly.vertices.length >= 2) {
        for (int i = 0; i < poly.vertices.length - 1; i++) {
          segments.add(
            _DiagSegment(
              start: poly.vertices[i],
              end: poly.vertices[i + 1],
              points: [poly.vertices[i], poly.vertices[i + 1]],
            ),
          );
        }
      }
    }

    final chainResult = _analyzeChains(segments, tolerance: 0.5);
    for (final loop in chainResult.closedLoops) {
      closedProfiles++;
      if (_isSlotLikeLoop(loop)) {
        slotProfiles++;
      }
    }

    for (final chain in chainResult.openChains) {
      openProfiles++;
      errorLocations.add(
        DxfDiagnosticErrorLocation(
          point: chain.first,
          issueType: 'unclosedLoop',
          description: 'Open loop start endpoint',
        ),
      );
      if (chain.length > 1) {
        errorLocations.add(
          DxfDiagnosticErrorLocation(
            point: chain.last,
            issueType: 'unclosedLoop',
            description: 'Open loop end endpoint',
          ),
        );
      }
    }

    errorLocations.addAll(chainResult.gapErrors);
    final geometryGaps = chainResult.gapErrors.length;

    final warnings = <String>[];
    if (duplicates > 0) warnings.add('$duplicates duplicate entities detected.');
    if (zeroLength > 0) warnings.add('$zeroLength zero-length segments detected.');
    if (geometryGaps > 0) warnings.add('$geometryGaps loose endpoint gaps found.');
    if (openProfiles > 0) warnings.add('$openProfiles unclosed profile loops detected.');

    return DxfDiagnosticsReport(
      totalEntities: parsed.entities.length,
      entityCountsByType: typeCounts,
      closedProfilesCount: closedProfiles,
      openProfilesCount: openProfiles,
      slotProfilesCount: slotProfiles,
      bendCandidatesCount: bendCandidates,
      duplicateEntitiesCount: duplicates,
      zeroLengthEntitiesCount: zeroLength,
      geometryGapsCount: geometryGaps,
      warnings: warnings,
      layersFound: layers,
      errorLocations: errorLocations,
      parsedData: parsed,
    );
  }

  /// Heals raw DXF geometry non-destructively by removing duplicates,
  /// stripping zero-length segments, and closing micro-gaps.
  static DxfHealingResult heal(
    DxfParsedData parsed, {
    bool removeDuplicates = true,
    bool removeZeroLength = true,
    double gapToleranceMm = 0.5,
  }) {
    var rawEntities = List<DxfRawEntity>.from(parsed.entities);

    int dupCount = 0;
    int zeroCount = 0;
    int gapCount = 0;

    // 1. Remove Zero-Length lines
    if (removeZeroLength) {
      final initialCount = rawEntities.length;
      rawEntities.removeWhere((e) => e is DxfRawLine && e.length < 0.01);
      zeroCount = initialCount - rawEntities.length;
    }

    // 2. Remove Duplicates & Redundant Collinear Entities (Lines, Arcs, Polylines)
    if (removeDuplicates) {
      final cleanEntities = <DxfRawEntity>[];
      for (final e in rawEntities) {
        if (e is DxfRawLine) {
          bool isRedundant = false;
          for (int i = 0; i < cleanEntities.length; i++) {
            final c = cleanEntities[i];
            if (c is DxfRawLine) {
              if (_isDuplicateLine(c, e) ||
                  _isCollinearSubsegment(e.p1, e.p2, c.p1, c.p2)) {
                isRedundant = true;
                dupCount++;
                break;
              } else if (_isCollinearSubsegment(c.p1, c.p2, e.p1, e.p2)) {
                cleanEntities[i] = e;
                isRedundant = true;
                dupCount++;
                break;
              }
            }
          }
          if (isRedundant) continue;
        } else if (e is DxfRawArc) {
          final isDup = cleanEntities.any(
            (c) => c is DxfRawArc && _isDuplicateArc(c, e),
          );
          if (isDup) {
            dupCount++;
            continue;
          }
        } else if (e is DxfRawPolyline) {
          final isDup = cleanEntities.any(
            (c) => c is DxfRawPolyline && _isDuplicatePolyline(c, e),
          );
          if (isDup) {
            dupCount++;
            continue;
          }
        }
        cleanEntities.add(e);
      }
      rawEntities = cleanEntities;
    }

    // 3. Heal Endpoint Micro-Gaps across Lines and Polylines
    if (gapToleranceMm > 0.0) {
      final anchors = <CadPoint2D>[];
      for (final e in rawEntities) {
        if (e is DxfRawArc) {
          anchors.add(_arcStart(e));
          anchors.add(_arcEnd(e));
        } else if (e is DxfRawLine) {
          anchors.add(e.p1);
          anchors.add(e.p2);
        } else if (e is DxfRawPolyline && e.vertices.isNotEmpty) {
          anchors.add(e.vertices.first);
          anchors.add(e.vertices.last);
        }
      }

      final updatedEntities = <DxfRawEntity>[];
      for (final e in rawEntities) {
        if (e is DxfRawLine) {
          var p1 = e.p1;
          var p2 = e.p2;

          for (final a in anchors) {
            final d1 = p1.distanceTo(a);
            if (d1 > 0.001 && d1 <= gapToleranceMm) {
              p1 = a;
              gapCount++;
              break;
            }
          }
          for (final a in anchors) {
            final d2 = p2.distanceTo(a);
            if (d2 > 0.001 && d2 <= gapToleranceMm) {
              p2 = a;
              gapCount++;
              break;
            }
          }
          updatedEntities.add(DxfRawLine(
            p1: p1,
            p2: p2,
            layer: e.layer,
            colorIndex: e.colorIndex,
          ));
        } else if (e is DxfRawPolyline && !e.isClosed && e.vertices.length >= 2) {
          final vList = List<CadPoint2D>.from(e.vertices);
          var first = vList.first;
          var last = vList.last;
          for (final a in anchors) {
            final d = first.distanceTo(a);
            if (d > 0.001 && d <= gapToleranceMm) {
              first = a;
              vList[0] = a;
              gapCount++;
              break;
            }
          }
          for (final a in anchors) {
            final d = last.distanceTo(a);
            if (d > 0.001 && d <= gapToleranceMm) {
              last = a;
              vList[vList.length - 1] = a;
              gapCount++;
              break;
            }
          }
          updatedEntities.add(DxfRawPolyline(
            vertices: vList,
            isClosed: e.isClosed,
            layer: e.layer,
            colorIndex: e.colorIndex,
          ));
        } else {
          updatedEntities.add(e);
        }
      }
      rawEntities = updatedEntities;
    }

    final healedData = DxfParsedData(
      entities: rawEntities,
      layers: parsed.layers,
    );

    return DxfHealingResult(
      healedData: healedData,
      duplicatesRemoved: dupCount,
      zeroLengthRemoved: zeroCount,
      gapsHealed: gapCount,
    );
  }

  static ({
    List<List<CadPoint2D>> closedLoops,
    List<List<CadPoint2D>> openChains,
    List<DxfDiagnosticErrorLocation> gapErrors,
  }) _analyzeChains(List<_DiagSegment> segments, {double tolerance = 0.5}) {
    final pool = <_DiagSegment>[];
    for (final s in segments) {
      bool isRedundant = false;
      for (int i = 0; i < pool.length; i++) {
        final existing = pool[i];
        if ((s.start.distanceTo(existing.start) < 0.05 &&
                s.end.distanceTo(existing.end) < 0.05) ||
            (s.start.distanceTo(existing.end) < 0.05 &&
                s.end.distanceTo(existing.start) < 0.05)) {
          isRedundant = true;
          break;
        }
        if (s.points.length == 2 && existing.points.length == 2) {
          if (_isCollinearSubsegment(s.start, s.end, existing.start, existing.end)) {
            isRedundant = true;
            break;
          } else if (_isCollinearSubsegment(existing.start, existing.end, s.start, s.end)) {
            pool[i] = s;
            isRedundant = true;
            break;
          }
        }
      }
      if (!isRedundant) pool.add(s);
    }

    final closedLoops = <List<CadPoint2D>>[];
    final openChains = <List<CadPoint2D>>[];
    final gapErrors = <DxfDiagnosticErrorLocation>[];


    while (pool.isNotEmpty) {
      var currentSeg = pool.removeAt(0);
      final currentLoop = List<CadPoint2D>.from(currentSeg.points);
      bool closed = false;

      while (pool.isNotEmpty) {
        final tail = currentLoop.last;
        if (currentLoop.length > 2 && tail.distanceTo(currentLoop.first) <= tolerance) {
          final closeDist = tail.distanceTo(currentLoop.first);
          if (closeDist > 0.01) {
            gapErrors.add(
              DxfDiagnosticErrorLocation(
                point: CadPoint2D(
                  (tail.x + currentLoop.first.x) / 2,
                  (tail.y + currentLoop.first.y) / 2,
                ),
                issueType: 'microGap',
                description:
                    'Micro-gap between loop endpoints (${closeDist.toStringAsFixed(2)} mm)',
              ),
            );
          }
          closed = true;
          break;
        }

        int matchIdx = -1;
        bool reverse = false;
        double bestDist = double.infinity;

        for (int i = 0; i < pool.length; i++) {
          final s = pool[i];
          final dStart = s.start.distanceTo(tail);
          final dEnd = s.end.distanceTo(tail);
          if (dStart <= tolerance && dStart < bestDist) {
            bestDist = dStart;
            matchIdx = i;
            reverse = false;
          } else if (dEnd <= tolerance && dEnd < bestDist) {
            bestDist = dEnd;
            matchIdx = i;
            reverse = true;
          }
        }

        if (matchIdx != -1) {
          if (bestDist > 0.01) {
            final matchedPt = reverse ? pool[matchIdx].end : pool[matchIdx].start;
            gapErrors.add(
              DxfDiagnosticErrorLocation(
                point: CadPoint2D(
                  (tail.x + matchedPt.x) / 2,
                  (tail.y + matchedPt.y) / 2,
                ),
                issueType: 'microGap',
                description:
                    'Micro-gap between endpoints (${bestDist.toStringAsFixed(2)} mm)',
              ),
            );
          }
          final nextSeg = pool.removeAt(matchIdx);
          final ptsToAdd = reverse ? nextSeg.points.reversed.toList() : nextSeg.points;
          currentLoop.addAll(ptsToAdd.skip(1));
        } else {
          break;
        }
      }

      if (!closed &&
          currentLoop.length > 2 &&
          currentLoop.last.distanceTo(currentLoop.first) <= tolerance) {
        final closeDist = currentLoop.last.distanceTo(currentLoop.first);
        if (closeDist > 0.01) {
          gapErrors.add(
            DxfDiagnosticErrorLocation(
              point: CadPoint2D(
                (currentLoop.last.x + currentLoop.first.x) / 2,
                (currentLoop.last.y + currentLoop.first.y) / 2,
              ),
              issueType: 'microGap',
              description:
                  'Micro-gap between loop endpoints (${closeDist.toStringAsFixed(2)} mm)',
            ),
          );
        }
        closed = true;
      }

      if (closed) {
        closedLoops.add(currentLoop);
      } else {
        openChains.add(currentLoop);
      }
    }

    return (closedLoops: closedLoops, openChains: openChains, gapErrors: gapErrors);
  }

  static CadPoint2D _arcStart(DxfRawArc a) {
    final rad = a.startAngleDeg * math.pi / 180.0;
    return CadPoint2D(
      a.center.x + a.radius * math.cos(rad),
      a.center.y + a.radius * math.sin(rad),
    );
  }

  static CadPoint2D _arcEnd(DxfRawArc a) {
    final rad = a.endAngleDeg * math.pi / 180.0;
    return CadPoint2D(
      a.center.x + a.radius * math.cos(rad),
      a.center.y + a.radius * math.sin(rad),
    );
  }

  static bool _isDuplicateLine(DxfRawLine a, DxfRawLine b) {
    const eps = 0.05;
    final fwd = a.p1.distanceTo(b.p1) < eps && a.p2.distanceTo(b.p2) < eps;
    final rev = a.p1.distanceTo(b.p2) < eps && a.p2.distanceTo(b.p1) < eps;
    return fwd || rev;
  }

  static bool _isCollinearSubsegment(
    CadPoint2D b1,
    CadPoint2D b2,
    CadPoint2D a1,
    CadPoint2D a2, {
    double tolerance = 0.05,
  }) {
    final dxA = a2.x - a1.x;
    final dyA = a2.y - a1.y;
    final lenSqA = dxA * dxA + dyA * dyA;
    if (lenSqA < 1e-6) return false;
    final lenA = math.sqrt(lenSqA);
    final ux = dxA / lenA;
    final uy = dyA / lenA;
    final nx = -uy;
    final ny = ux;

    final dist1 = ((b1.x - a1.x) * nx + (b1.y - a1.y) * ny).abs();
    final dist2 = ((b2.x - a1.x) * nx + (b2.y - a1.y) * ny).abs();
    if (dist1 > tolerance || dist2 > tolerance) return false;

    final t1 = (b1.x - a1.x) * ux + (b1.y - a1.y) * uy;
    final t2 = (b2.x - a1.x) * ux + (b2.y - a1.y) * uy;
    final minT = math.min(t1, t2);
    final maxT = math.max(t1, t2);

    return minT >= -tolerance && maxT <= lenA + tolerance;
  }

  static bool _isDuplicatePolyline(
    DxfRawPolyline a,
    DxfRawPolyline b, {
    double tolerance = 0.05,
  }) {
    if (a.vertices.length != b.vertices.length) return false;
    if (a.vertices.isEmpty) return true;
    final n = a.vertices.length;

    for (int shift = 0; shift < n; shift++) {
      bool matchFwd = true;
      for (int i = 0; i < n; i++) {
        if (a.vertices[i].distanceTo(b.vertices[(i + shift) % n]) > tolerance) {
          matchFwd = false;
          break;
        }
      }
      if (matchFwd) return true;

      bool matchRev = true;
      for (int i = 0; i < n; i++) {
        if (a.vertices[i].distanceTo(b.vertices[(n - 1 - i + shift) % n]) >
            tolerance) {
          matchRev = false;
          break;
        }
      }
      if (matchRev) return true;
    }
    return false;
  }

  static bool _isDuplicateArc(DxfRawArc a, DxfRawArc b) {
    return a.center.distanceTo(b.center) < 0.05 &&
        (a.radius - b.radius).abs() < 0.05 &&
        (a.startAngleDeg - b.startAngleDeg).abs() < 0.5 &&
        (a.endAngleDeg - b.endAngleDeg).abs() < 0.5;
  }

  static bool _isSlotLikeLoop(List<CadPoint2D> pts) {
    final clean = <CadPoint2D>[];
    for (final p in pts) {
      if (clean.isEmpty || clean.last.distanceTo(p) > 0.01) {
        clean.add(p);
      }
    }
    if (clean.length > 3 && clean.first.distanceTo(clean.last) < 0.05) {
      clean.removeLast();
    }
    if (clean.length < 3) return false;

    if (clean.length == 4) {
      final side1 = clean[0].distanceTo(clean[1]);
      final side2 = clean[1].distanceTo(clean[2]);
      final l = math.max(side1, side2);
      final w = math.min(side1, side2);
      if (w < 0.5 || l > 150.0) return false;
      final ratio = l / w;
      return ratio >= 1.15 && ratio <= 15.0;
    }

    double maxDistSq = -1.0;
    CadPoint2D pA = clean.first;
    CadPoint2D pB = clean.first;
    for (int i = 0; i < clean.length; i++) {
      for (int j = i + 1; j < clean.length; j++) {
        final dx = clean[i].x - clean[j].x;
        final dy = clean[i].y - clean[j].y;
        final dSq = dx * dx + dy * dy;
        if (dSq > maxDistSq) {
          maxDistSq = dSq;
          pA = clean[i];
          pB = clean[j];
        }
      }
    }
    final length = math.sqrt(maxDistSq);
    if (length < 1.0 || length > 150.0) return false;

    final theta = math.atan2(pB.y - pA.y, pB.x - pA.x);
    final cosT = math.cos(theta);
    final sinT = math.sin(theta);
    double sumX = 0, sumY = 0;
    for (final p in clean) {
      sumX += p.x;
      sumY += p.y;
    }
    final centroid = CadPoint2D(sumX / clean.length, sumY / clean.length);

    double minV = double.infinity;
    double maxV = -double.infinity;
    for (final p in clean) {
      final v = -(p.x - centroid.x) * sinT + (p.y - centroid.y) * cosT;
      minV = math.min(minV, v);
      maxV = math.max(maxV, v);
    }
    final width = maxV - minV;
    if (width < 0.5) return false;

    final ratio = length / width;
    return ratio >= 1.15 && ratio <= 15.0;
  }
}

