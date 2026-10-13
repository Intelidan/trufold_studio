/// Bill of Materials (BOM) Item for fabrication and cutting lists.
class AssemblyBomItem {
  final String itemNumber;
  final String partMark;
  final String description;
  final String materialGrade;
  final String profile;
  final double lengthMm;
  final double widthMm;
  final double thicknessMm;
  final int quantity;
  final double unitWeightKg;
  final double totalWeightKg;
  final double cutLengthMm;
  final int holeCount;
  final int bendCount;
  final String finish;

  const AssemblyBomItem({
    required this.itemNumber,
    required this.partMark,
    required this.description,
    this.materialGrade = 'Stainless Steel 304',
    required this.profile,
    required this.lengthMm,
    required this.widthMm,
    required this.thicknessMm,
    required this.quantity,
    required this.unitWeightKg,
    required this.totalWeightKg,
    required this.cutLengthMm,
    this.holeCount = 0,
    this.bendCount = 0,
    this.finish = 'Mill Finish / Clean Weld',
  });
}

/// Comprehensive Bill of Materials report with fabrication cut list and weld summaries.
class AssemblyBomReport {
  final List<AssemblyBomItem> items;
  final double totalWeightKg;
  final int totalPartCount;
  final double totalWeldLengthMm;
  final int totalWeldCount;
  final DateTime generatedAt;
  final String assemblyTitle;

  AssemblyBomReport({
    required this.items,
    required this.totalWeightKg,
    required this.totalPartCount,
    required this.totalWeldLengthMm,
    required this.totalWeldCount,
    DateTime? generatedAt,
    this.assemblyTitle = 'Industrial Cable Ladder Assembly',
  }) : generatedAt = generatedAt ?? DateTime.now();

  /// Exports the BOM in RFC 4180 CSV format for ERP/Excel import.
  String toCsv() {
    final buf = StringBuffer();
    buf.writeln('Item,Part Mark,Description,Profile,Qty,Length (mm),Width (mm),Thk (mm),Unit Wt (kg),Total Wt (kg),Holes,Bends,Material,Finish');
    for (final it in items) {
      buf.writeln('${it.itemNumber},"${it.partMark}","${it.description}","${it.profile}",${it.quantity},${it.lengthMm.toStringAsFixed(1)},${it.widthMm.toStringAsFixed(1)},${it.thicknessMm.toStringAsFixed(1)},${it.unitWeightKg.toStringAsFixed(2)},${it.totalWeightKg.toStringAsFixed(2)},${it.holeCount},${it.bendCount},"${it.materialGrade}","${it.finish}"');
    }
    buf.writeln();
    buf.writeln('SUMMARY');
    buf.writeln('Total Parts,$totalPartCount');
    buf.writeln('Total Weight (kg),${totalWeightKg.toStringAsFixed(2)}');
    buf.writeln('Total Welds,$totalWeldCount');
    buf.writeln('Total Weld Length (mm),${totalWeldLengthMm.toStringAsFixed(1)}');
    return buf.toString();
  }

  /// Exports the BOM in clean GitHub Markdown table format.
  String toMarkdown() {
    final buf = StringBuffer();
    buf.writeln('# Bill of Materials (BOM) & Fabrication Cut List');
    buf.writeln('**Assembly:** $assemblyTitle  ');
    buf.writeln('**Generated:** ${generatedAt.toIso8601String().split('T').first}  ');
    buf.writeln('**Total Weight:** ${totalWeightKg.toStringAsFixed(2)} kg | **Parts:** $totalPartCount | **Welds:** $totalWeldCount (${(totalWeldLengthMm / 1000.0).toStringAsFixed(2)} m)  ');
    buf.writeln();
    buf.writeln('| Item | Mark | Description | Profile | Qty | Cut Length | Unit Wt | Total Wt | Holes | Material |');
    buf.writeln('| :--- | :--- | :--- | :--- | :---: | :---: | :---: | :---: | :---: | :--- |');
    for (final it in items) {
      buf.writeln('| ${it.itemNumber} | **${it.partMark}** | ${it.description} | ${it.profile} | ${it.quantity} | ${it.cutLengthMm.toStringAsFixed(0)} mm | ${it.unitWeightKg.toStringAsFixed(2)} kg | ${it.totalWeightKg.toStringAsFixed(2)} kg | ${it.holeCount} | ${it.materialGrade} |');
    }
    buf.writeln();
    buf.writeln('### Fabrication Weld Summary');
    buf.writeln('- **Total Fillet Weld Joints:** $totalWeldCount joints');
    buf.writeln('- **Total Fillet Bead Seam Length:** ${totalWeldLengthMm.toStringAsFixed(0)} mm (${(totalWeldLengthMm / 1000.0).toStringAsFixed(2)} m)');
    buf.writeln('- **Weld Specification:** Fillet Weld AWS D1.1 / EN ISO 2553 (Industrial Gold Bead)');
    return buf.toString();
  }
}
