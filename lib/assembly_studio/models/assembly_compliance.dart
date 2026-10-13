import 'package:flutter/material.dart';

/// Status of an industrial compliance verification check.
enum ComplianceStatus {
  pass,
  warning,
  fail,
}

/// A single compliance criterion evaluated against OSHA 1910 and EN ISO 14122-4 standards.
class ComplianceItemResult {
  final String id;
  final String title;
  final String standardCode;
  final ComplianceStatus status;
  final double? measuredValueMm;
  final double minAllowedMm;
  final double maxAllowedMm;
  final String units;
  final String description;
  final String recommendation;
  final String fixActionId;

  const ComplianceItemResult({
    required this.id,
    required this.title,
    required this.standardCode,
    required this.status,
    this.measuredValueMm,
    required this.minAllowedMm,
    required this.maxAllowedMm,
    this.units = 'mm',
    required this.description,
    required this.recommendation,
    this.fixActionId = '',
  });

  bool get isPass => status == ComplianceStatus.pass;
  bool get isWarning => status == ComplianceStatus.warning;
  bool get isFail => status == ComplianceStatus.fail;

  Color get statusColor {
    switch (status) {
      case ComplianceStatus.pass:
        return const Color(0xFF10B981); // Emerald green
      case ComplianceStatus.warning:
        return const Color(0xFFF59E0B); // Amber
      case ComplianceStatus.fail:
        return const Color(0xFFEF4444); // Crimson red
    }
  }

  String get statusLabel {
    switch (status) {
      case ComplianceStatus.pass:
        return 'PASS';
      case ComplianceStatus.warning:
        return 'WARNING';
      case ComplianceStatus.fail:
        return 'FAIL';
    }
  }

  IconData get statusIcon {
    switch (status) {
      case ComplianceStatus.pass:
        return Icons.check_circle_rounded;
      case ComplianceStatus.warning:
        return Icons.warning_amber_rounded;
      case ComplianceStatus.fail:
        return Icons.cancel_rounded;
    }
  }
}

/// Comprehensive OSHA 1910 and EN ISO 14122-4 audit report for the ladder assembly.
class AssemblyComplianceReport {
  final List<ComplianceItemResult> items;
  final DateTime evaluatedAt;
  final double ladderTotalHeightMm;
  final int totalRungCount;

  AssemblyComplianceReport({
    required this.items,
    DateTime? evaluatedAt,
    this.ladderTotalHeightMm = 0.0,
    this.totalRungCount = 0,
  }) : evaluatedAt = evaluatedAt ?? DateTime.now();

  ComplianceStatus get overallStatus {
    if (items.any((i) => i.status == ComplianceStatus.fail)) {
      return ComplianceStatus.fail;
    }
    if (items.any((i) => i.status == ComplianceStatus.warning)) {
      return ComplianceStatus.warning;
    }
    return ComplianceStatus.pass;
  }

  bool get isCompliant => overallStatus == ComplianceStatus.pass;

  int get passCount => items.where((i) => i.status == ComplianceStatus.pass).length;
  int get warnCount => items.where((i) => i.status == ComplianceStatus.warning).length;
  int get failCount => items.where((i) => i.status == ComplianceStatus.fail).length;

  Color get badgeColor {
    switch (overallStatus) {
      case ComplianceStatus.pass:
        return const Color(0xFF10B981);
      case ComplianceStatus.warning:
        return const Color(0xFFF59E0B);
      case ComplianceStatus.fail:
        return const Color(0xFFEF4444);
    }
  }

  String get badgeLabel {
    switch (overallStatus) {
      case ComplianceStatus.pass:
        return 'OSHA / ISO: PASS ($passCount/${items.length})';
      case ComplianceStatus.warning:
        return 'OSHA / ISO: $warnCount WARN ($passCount/${items.length})';
      case ComplianceStatus.fail:
        return 'OSHA / ISO: $failCount FAIL ($passCount/${items.length})';
    }
  }
}
