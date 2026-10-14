import 'package:flutter/material.dart';

abstract class FinalCADViewModel {
  bool get isExportingFile;
  Future<String?> generateIndustrialSTLFilePayload();
}

Widget buildManufacturingExportToolbar(BuildContext context, FinalCADViewModel vm) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Divider(color: Colors.white12, height: 30),
      const Text(
        "FABRICATION EXPORT",
        style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      ElevatedButton.icon(
        style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(40), backgroundColor: Colors.blueAccent),
        icon: vm.isExportingFile
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.print, size: 14, color: Colors.white),
        label: const Text(
          "GENERATE STL FOR 3D PRINTING",
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        onPressed: vm.isExportingFile
            ? null
            : () async {
                final String? stlFileContent = await vm.generateIndustrialSTLFilePayload();

                if (stlFileContent != null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: Colors.green,
                      content: Text(
                        "STL Compiled Successfully! (${(stlFileContent.length / 1024).toStringAsFixed(1)} KB) ready for print file storage pipelines.",
                      ),
                    ),
                  );
                }
              },
      ),
    ],
  );
}
