import 'package:flutter/material.dart';
import '../../models/assembly_part.dart';
import '../../viewmodels/assembly_studio_viewmodel.dart';

/// Left sidebar palette containing common ladder parts and the active assembly tree.
class AssemblyPartsPalette extends StatelessWidget {
  final AssemblyStudioViewModel viewModel;

  const AssemblyPartsPalette({
    super.key,
    required this.viewModel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 290,
      decoration: const BoxDecoration(
        color: Colors.white, // Crisp white background
        border: Border(
          right: BorderSide(color: Color(0xFFE2E8F0), width: 1.0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1.0)),
              color: Color(0xFFF8FAFC),
            ),
            child: Row(
              children: [
                const Icon(Icons.category_rounded, color: Color(0xFF0284C7), size: 18),
                const SizedBox(width: 8),
                const Text(
                  'PARTS & ACCESSORIES',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${viewModel.doc.parts.length} parts',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8)),
                  ),
                ),
              ],
            ),
          ),

          // Quick Demos / Template Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  onPressed: viewModel.loadStandardLadderDemo,
                  icon: const Icon(Icons.view_headline_rounded, size: 12),
                  label: const Text('Ladder', style: TextStyle(fontSize: 10)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: viewModel.loadCableTrayDemo,
                  icon: const Icon(Icons.dashboard_outlined, size: 12),
                  label: const Text('Tray', style: TextStyle(fontSize: 10)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: viewModel.loadCableTrunkingDemo,
                  icon: const Icon(Icons.view_stream_rounded, size: 12),
                  label: const Text('Trunking', style: TextStyle(fontSize: 10)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => viewModel.importDsfFiles(context: context),
                  icon: const Icon(Icons.file_download_outlined, size: 12, color: Color(0xFF0284C7)),
                  label: const Text('Import DSF', style: TextStyle(fontSize: 10, color: Color(0xFF0284C7), fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    side: const BorderSide(color: Color(0xFF0284C7)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFE2E8F0)),

          // Scrollable Body: Add Parts Section + Assembly Tree
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                // SECTION 1: COMMON MODULAR PARTS LIBRARY
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    'SPAWN COMMON PARTS',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ),

                // 1. Slotted Rung Card
                _buildPartSpawnTile(
                  partType: AssemblyPartType.rung,
                  title: 'Slotted C-Rung (40x20)',
                  subtitle: 'Cable tie obround slots',
                  accentColor: const Color(0xFF0284C7),
                  defaultPlacement: const PendingPartPlacement(
                    type: AssemblyPartType.rung,
                    name: 'Slotted C-Rung (600mm)',
                    length: 600.0,
                    height: 40.0,
                    flangeWidth: 20.0,
                    thickness: 1.5,
                    color: Color(0xFF38BDF8),
                  ),
                  trailingMenu: [
                    PopupMenuItem(
                      onTap: () => viewModel.setPendingPlacement(const PendingPartPlacement(
                        type: AssemblyPartType.rung,
                        name: 'Slotted C-Rung (300mm)',
                        length: 300.0,
                        height: 40.0,
                        flangeWidth: 20.0,
                        thickness: 1.5,
                        color: Color(0xFF38BDF8),
                      )),
                      child: const Text('Width: 300 mm', style: TextStyle(fontSize: 12)),
                    ),
                    PopupMenuItem(
                      onTap: () => viewModel.setPendingPlacement(const PendingPartPlacement(
                        type: AssemblyPartType.rung,
                        name: 'Slotted C-Rung (450mm)',
                        length: 450.0,
                        height: 40.0,
                        flangeWidth: 20.0,
                        thickness: 1.5,
                        color: Color(0xFF38BDF8),
                      )),
                      child: const Text('Width: 450 mm', style: TextStyle(fontSize: 12)),
                    ),
                    PopupMenuItem(
                      onTap: () => viewModel.setPendingPlacement(const PendingPartPlacement(
                        type: AssemblyPartType.rung,
                        name: 'Slotted C-Rung (600mm)',
                        length: 600.0,
                        height: 40.0,
                        flangeWidth: 20.0,
                        thickness: 1.5,
                        color: Color(0xFF38BDF8),
                      )),
                      child: const Text('Width: 600 mm (Default)', style: TextStyle(fontSize: 12)),
                    ),
                    PopupMenuItem(
                      onTap: () => viewModel.setPendingPlacement(const PendingPartPlacement(
                        type: AssemblyPartType.rung,
                        name: 'Slotted C-Rung (750mm)',
                        length: 750.0,
                        height: 40.0,
                        flangeWidth: 20.0,
                        thickness: 1.5,
                        color: Color(0xFF38BDF8),
                      )),
                      child: const Text('Width: 750 mm', style: TextStyle(fontSize: 12)),
                    ),
                    PopupMenuItem(
                      onTap: () => viewModel.setPendingPlacement(const PendingPartPlacement(
                        type: AssemblyPartType.rung,
                        name: 'Slotted C-Rung (900mm)',
                        length: 900.0,
                        height: 40.0,
                        flangeWidth: 20.0,
                        thickness: 1.5,
                        color: Color(0xFF38BDF8),
                      )),
                      child: const Text('Width: 900 mm', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // 2. Straight Side Rail Card
                _buildPartSpawnTile(
                  partType: AssemblyPartType.straightRail,
                  title: 'Straight Side Rail',
                  subtitle: '20mm Flange • Splice holes',
                  accentColor: const Color(0xFF10B981),
                  defaultPlacement: const PendingPartPlacement(
                    type: AssemblyPartType.straightRail,
                    name: 'Straight Side Rail (1,000mm)',
                    length: 1000.0,
                    height: 100.0,
                    flangeWidth: 20.0,
                    thickness: 2.0,
                    color: Color(0xFF64748B),
                  ),
                  trailingMenu: [
                    PopupMenuItem(
                      onTap: () => viewModel.setPendingPlacement(const PendingPartPlacement(
                        type: AssemblyPartType.straightRail,
                        name: 'Straight Side Rail (500mm)',
                        length: 500.0,
                        height: 100.0,
                        flangeWidth: 20.0,
                        thickness: 2.0,
                        color: Color(0xFF64748B),
                      )),
                      child: const Text('Length: 500 mm (Coupler fit)', style: TextStyle(fontSize: 12)),
                    ),
                    PopupMenuItem(
                      onTap: () => viewModel.setPendingPlacement(const PendingPartPlacement(
                        type: AssemblyPartType.straightRail,
                        name: 'Straight Side Rail (1,000mm)',
                        length: 1000.0,
                        height: 100.0,
                        flangeWidth: 20.0,
                        thickness: 2.0,
                        color: Color(0xFF64748B),
                      )),
                      child: const Text('Length: 1,000 mm (Standard)', style: TextStyle(fontSize: 12)),
                    ),
                    PopupMenuItem(
                      onTap: () => viewModel.setPendingPlacement(const PendingPartPlacement(
                        type: AssemblyPartType.straightRail,
                        name: 'Straight Side Rail (1,500mm)',
                        length: 1500.0,
                        height: 100.0,
                        flangeWidth: 20.0,
                        thickness: 2.0,
                        color: Color(0xFF64748B),
                      )),
                      child: const Text('Length: 1,500 mm', style: TextStyle(fontSize: 12)),
                    ),
                    PopupMenuItem(
                      onTap: () => viewModel.setPendingPlacement(const PendingPartPlacement(
                        type: AssemblyPartType.straightRail,
                        name: 'Straight Side Rail (2,000mm)',
                        length: 2000.0,
                        height: 100.0,
                        flangeWidth: 20.0,
                        thickness: 2.0,
                        color: Color(0xFF64748B),
                      )),
                      child: const Text('Length: 2,000 mm', style: TextStyle(fontSize: 12)),
                    ),
                    PopupMenuItem(
                      onTap: () => viewModel.setPendingPlacement(const PendingPartPlacement(
                        type: AssemblyPartType.straightRail,
                        name: 'Straight Side Rail (3,000mm)',
                        length: 3000.0,
                        height: 100.0,
                        flangeWidth: 20.0,
                        thickness: 2.0,
                        color: Color(0xFF64748B),
                      )),
                      child: const Text('Length: 3,000 mm (Full section)', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // 3. Multi-Segment Bent Rail Card (with Auto V-Notch on Flange)
                _buildPartSpawnTile(
                  partType: AssemblyPartType.bentRail,
                  title: 'Bent Rail (Multi-Segment)',
                  subtitle: 'Auto V-Notch Flange • Custom Bends',
                  accentColor: const Color(0xFFF59E0B),
                  defaultPlacement: const PendingPartPlacement(
                    type: AssemblyPartType.bentRail,
                    name: 'Bent Rail (3-Segment 45°)',
                    length: 850.0,
                    height: 100.0,
                    flangeWidth: 20.0,
                    thickness: 2.0,
                    color: Color(0xFF64748B),
                  ),
                  trailingMenu: [
                    PopupMenuItem(
                      onTap: () => viewModel.setPendingPlacement(const PendingPartPlacement(
                        type: AssemblyPartType.bentRail,
                        name: '3-Segment 45° Branch Rail',
                        length: 850.0,
                        height: 100.0,
                        flangeWidth: 20.0,
                        thickness: 2.0,
                        color: Color(0xFF64748B),
                      )),
                      child: const Text('3-Segment 45° Branch (Auto V-Notch)', style: TextStyle(fontSize: 12)),
                    ),
                    PopupMenuItem(
                      onTap: () => viewModel.setPendingPlacement(const PendingPartPlacement(
                        type: AssemblyPartType.bentRail,
                        name: '2-Segment 90° Corner Rail',
                        length: 700.0,
                        height: 100.0,
                        flangeWidth: 20.0,
                        thickness: 2.0,
                        color: Color(0xFF64748B),
                      )),
                      child: const Text('2-Segment 90° Corner Rail', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // 4. Structural C-Channel Card
                _buildPartSpawnTile(
                  partType: AssemblyPartType.channel,
                  title: 'C-Channel (Structural)',
                  subtitle: '75x35mm Web & Flange',
                  accentColor: const Color(0xFF475569),
                  defaultPlacement: const PendingPartPlacement(
                    type: AssemblyPartType.channel,
                    name: '75x35mm C-Channel (1,500mm)',
                    length: 1500.0,
                    height: 75.0,
                    flangeWidth: 35.0,
                    thickness: 3.0,
                    color: Color(0xFF546E7A),
                  ),
                  trailingMenu: [
                    PopupMenuItem(
                      onTap: () => viewModel.setPendingPlacement(const PendingPartPlacement(
                        type: AssemblyPartType.channel,
                        name: '50x25mm C-Channel',
                        length: 1500.0,
                        height: 50.0,
                        flangeWidth: 25.0,
                        thickness: 2.5,
                        color: Color(0xFF546E7A),
                      )),
                      child: const Text('50 x 25 mm C-Channel', style: TextStyle(fontSize: 12)),
                    ),
                    PopupMenuItem(
                      onTap: () => viewModel.setPendingPlacement(const PendingPartPlacement(
                        type: AssemblyPartType.channel,
                        name: '75x35mm C-Channel (Standard)',
                        length: 1500.0,
                        height: 75.0,
                        flangeWidth: 35.0,
                        thickness: 3.0,
                        color: Color(0xFF546E7A),
                      )),
                      child: const Text('75 x 35 mm C-Channel (Standard)', style: TextStyle(fontSize: 12)),
                    ),
                    PopupMenuItem(
                      onTap: () => viewModel.setPendingPlacement(const PendingPartPlacement(
                        type: AssemblyPartType.channel,
                        name: '100x50mm Heavy Channel',
                        length: 1500.0,
                        height: 100.0,
                        flangeWidth: 50.0,
                        thickness: 4.0,
                        color: Color(0xFF546E7A),
                      )),
                      child: const Text('100 x 50 mm Heavy Channel', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // 5. Structural L-Angle Card
                _buildPartSpawnTile(
                  partType: AssemblyPartType.angle,
                  title: 'L-Angle (Angle Iron)',
                  subtitle: '50x50x4mm Equal Leg',
                  accentColor: const Color(0xFF64748B),
                  defaultPlacement: const PendingPartPlacement(
                    type: AssemblyPartType.angle,
                    name: '50x50x4mm L-Angle (1,200mm)',
                    length: 1200.0,
                    height: 50.0,
                    flangeWidth: 50.0,
                    thickness: 4.0,
                    color: Color(0xFF455A64),
                  ),
                  trailingMenu: [
                    PopupMenuItem(
                      onTap: () => viewModel.setPendingPlacement(const PendingPartPlacement(
                        type: AssemblyPartType.angle,
                        name: '40x40x3mm L-Angle',
                        length: 1200.0,
                        height: 40.0,
                        flangeWidth: 40.0,
                        thickness: 3.0,
                        color: Color(0xFF455A64),
                      )),
                      child: const Text('40 x 40 x 3 mm Angle', style: TextStyle(fontSize: 12)),
                    ),
                    PopupMenuItem(
                      onTap: () => viewModel.setPendingPlacement(const PendingPartPlacement(
                        type: AssemblyPartType.angle,
                        name: '50x50x4mm L-Angle (Standard)',
                        length: 1200.0,
                        height: 50.0,
                        flangeWidth: 50.0,
                        thickness: 4.0,
                        color: Color(0xFF455A64),
                      )),
                      child: const Text('50 x 50 x 4 mm Angle (Standard)', style: TextStyle(fontSize: 12)),
                    ),
                    PopupMenuItem(
                      onTap: () => viewModel.setPendingPlacement(const PendingPartPlacement(
                        type: AssemblyPartType.angle,
                        name: '75x75x6mm Heavy Angle',
                        length: 1200.0,
                        height: 75.0,
                        flangeWidth: 75.0,
                        thickness: 6.0,
                        color: Color(0xFF455A64),
                      )),
                      child: const Text('75 x 75 x 6 mm Heavy Angle', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // 6. Round Solid Rod Card
                _buildPartSpawnTile(
                  partType: AssemblyPartType.rod,
                  title: 'Round Rod / Bar',
                  subtitle: '⌀20mm Solid Rod',
                  accentColor: const Color(0xFF0D9488),
                  defaultPlacement: const PendingPartPlacement(
                    type: AssemblyPartType.rod,
                    name: '⌀20mm Round Rod (1,000mm)',
                    length: 1000.0,
                    height: 20.0,
                    flangeWidth: 20.0,
                    thickness: 20.0,
                    color: Color(0xFF78909C),
                  ),
                  trailingMenu: [
                    PopupMenuItem(
                      onTap: () => viewModel.setPendingPlacement(const PendingPartPlacement(
                        type: AssemblyPartType.rod,
                        name: '⌀12mm Round Rod',
                        length: 1000.0,
                        height: 12.0,
                        flangeWidth: 12.0,
                        thickness: 12.0,
                        color: Color(0xFF78909C),
                      )),
                      child: const Text('⌀12 mm Round Rod', style: TextStyle(fontSize: 12)),
                    ),
                    PopupMenuItem(
                      onTap: () => viewModel.setPendingPlacement(const PendingPartPlacement(
                        type: AssemblyPartType.rod,
                        name: '⌀16mm Round Rod',
                        length: 1000.0,
                        height: 16.0,
                        flangeWidth: 16.0,
                        thickness: 16.0,
                        color: Color(0xFF78909C),
                      )),
                      child: const Text('⌀16 mm Round Rod', style: TextStyle(fontSize: 12)),
                    ),
                    PopupMenuItem(
                      onTap: () => viewModel.setPendingPlacement(const PendingPartPlacement(
                        type: AssemblyPartType.rod,
                        name: '⌀20mm Round Rod (Standard)',
                        length: 1000.0,
                        height: 20.0,
                        flangeWidth: 20.0,
                        thickness: 20.0,
                        color: Color(0xFF78909C),
                      )),
                      child: const Text('⌀20 mm Round Rod (Standard)', style: TextStyle(fontSize: 12)),
                    ),
                    PopupMenuItem(
                      onTap: () => viewModel.setPendingPlacement(const PendingPartPlacement(
                        type: AssemblyPartType.rod,
                        name: '⌀25mm Round Rod',
                        length: 1000.0,
                        height: 25.0,
                        flangeWidth: 25.0,
                        thickness: 25.0,
                        color: Color(0xFF78909C),
                      )),
                      child: const Text('⌀25 mm Round Rod', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // 7. Rectangular Flat Bar Card
                _buildPartSpawnTile(
                  partType: AssemblyPartType.bar,
                  title: 'Flat Bar (Solid)',
                  subtitle: '40x6mm Solid Bar',
                  accentColor: const Color(0xFF6366F1),
                  defaultPlacement: const PendingPartPlacement(
                    type: AssemblyPartType.bar,
                    name: '40x6mm Flat Bar (1,000mm)',
                    length: 1000.0,
                    height: 40.0,
                    flangeWidth: 6.0,
                    thickness: 6.0,
                    color: Color(0xFF607D8B),
                  ),
                  trailingMenu: [
                    PopupMenuItem(
                      onTap: () => viewModel.setPendingPlacement(const PendingPartPlacement(
                        type: AssemblyPartType.bar,
                        name: '30x5mm Flat Bar',
                        length: 1000.0,
                        height: 30.0,
                        flangeWidth: 5.0,
                        thickness: 5.0,
                        color: Color(0xFF607D8B),
                      )),
                      child: const Text('30 x 5 mm Flat Bar', style: TextStyle(fontSize: 12)),
                    ),
                    PopupMenuItem(
                      onTap: () => viewModel.setPendingPlacement(const PendingPartPlacement(
                        type: AssemblyPartType.bar,
                        name: '40x6mm Flat Bar (Standard)',
                        length: 1000.0,
                        height: 40.0,
                        flangeWidth: 6.0,
                        thickness: 6.0,
                        color: Color(0xFF607D8B),
                      )),
                      child: const Text('40 x 6 mm Flat Bar (Standard)', style: TextStyle(fontSize: 12)),
                    ),
                    PopupMenuItem(
                      onTap: () => viewModel.setPendingPlacement(const PendingPartPlacement(
                        type: AssemblyPartType.bar,
                        name: '50x8mm Flat Bar',
                        length: 1000.0,
                        height: 50.0,
                        flangeWidth: 8.0,
                        thickness: 8.0,
                        color: Color(0xFF607D8B),
                      )),
                      child: const Text('50 x 8 mm Flat Bar', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // 8. Structural I-Beam Card
                _buildPartSpawnTile(
                  partType: AssemblyPartType.iBeam,
                  title: 'I-Beam (H-Beam)',
                  subtitle: '100x60mm Structural Section',
                  accentColor: const Color(0xFF1E293B),
                  defaultPlacement: const PendingPartPlacement(
                    type: AssemblyPartType.iBeam,
                    name: '100x60mm I-Beam (2,000mm)',
                    length: 2000.0,
                    height: 100.0,
                    flangeWidth: 60.0,
                    thickness: 4.5,
                    color: Color(0xFF37474F),
                  ),
                  trailingMenu: [
                    PopupMenuItem(
                      onTap: () => viewModel.setPendingPlacement(const PendingPartPlacement(
                        type: AssemblyPartType.iBeam,
                        name: '100x60mm I-Beam',
                        length: 2000.0,
                        height: 100.0,
                        flangeWidth: 60.0,
                        thickness: 4.5,
                        color: Color(0xFF37474F),
                      )),
                      child: const Text('100 x 60 mm I-Beam', style: TextStyle(fontSize: 12)),
                    ),
                    PopupMenuItem(
                      onTap: () => viewModel.setPendingPlacement(const PendingPartPlacement(
                        type: AssemblyPartType.iBeam,
                        name: '150x75mm I-Beam',
                        length: 2000.0,
                        height: 150.0,
                        flangeWidth: 75.0,
                        thickness: 5.5,
                        color: Color(0xFF37474F),
                      )),
                      child: const Text('150 x 75 mm I-Beam', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                const Divider(height: 1, color: Color(0xFFCBD5E1)),
                const SizedBox(height: 8),

                // SECTION 2: ASSEMBLY TREE & INSTANCES
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'ASSEMBLY TREE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    if (viewModel.selectedPart != null)
                      Text(
                        '1 selected',
                        style: TextStyle(fontSize: 10, color: Colors.blue.shade300),
                      ),
                  ],
                ),
                const SizedBox(height: 6),

                if (viewModel.doc.parts.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    alignment: Alignment.center,
                    child: const Text(
                      'No parts in assembly.\nClick any card above to spawn.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                  )
                else
                  ...viewModel.doc.parts.map((p) => _buildAssemblyPartRow(p)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPartSpawnTile({
    required AssemblyPartType partType,
    required String title,
    required String subtitle,
    required Color accentColor,
    required PendingPartPlacement defaultPlacement,
    List<PopupMenuEntry<dynamic>> trailingMenu = const [],
  }) {
    final isPending = viewModel.pendingPlacement?.type == partType;

    final tileContent = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isPending ? const Color(0xFFF0F9FF) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isPending ? const Color(0xFF0284C7) : const Color(0xFFE2E8F0),
          width: isPending ? 1.8 : 1.0,
        ),
        boxShadow: isPending
            ? [
                BoxShadow(
                  color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          // Genuine CAD Part Miniature Thumbnail
          _PartMiniatureThumbnail(
            partType: partType,
            accentColor: accentColor,
            size: 36,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isPending ? FontWeight.w700 : FontWeight.w600,
                          color: isPending ? const Color(0xFF0284C7) : const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    if (isPending)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'READY',
                          style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.white),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  isPending ? 'Click on drawing board to place' : subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isPending ? FontWeight.w600 : FontWeight.normal,
                    color: isPending ? const Color(0xFF0369A1) : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          if (trailingMenu.isNotEmpty)
            PopupMenuButton<dynamic>(
              tooltip: 'Options & Standard Sizes',
              icon: const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF64748B), size: 20),
              itemBuilder: (ctx) => trailingMenu,
            )
          else
            Icon(
              isPending ? Icons.check_circle_rounded : Icons.pan_tool_alt_rounded,
              color: isPending ? const Color(0xFF0284C7) : const Color(0xFF94A3B8),
              size: 16,
            ),
        ],
      ),
    );

    return Draggable<PendingPartPlacement>(
      data: defaultPlacement,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(color: Color(0x3F000000), blurRadius: 14, offset: Offset(0, 5)),
            ],
            border: Border.all(color: const Color(0xFF38BDF8), width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PartMiniatureThumbnail(
                partType: partType,
                accentColor: accentColor,
                size: 28,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.35,
        child: tileContent,
      ),
      child: InkWell(
        onTap: () {
          if (isPending) {
            viewModel.cancelPendingPlacement();
          } else {
            viewModel.setPendingPlacement(defaultPlacement);
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: tileContent,
      ),
    );
  }

  Widget _buildAssemblyPartRow(AssemblyPart part) {
    final isSelected = viewModel.selectedPart?.id == part.id;
    final weldCount = part.weldedToPartIds.length;

    IconData typeIcon;
    Color typeColor;
    switch (part.type) {
      case AssemblyPartType.rung:
        typeIcon = Icons.table_rows_rounded;
        typeColor = const Color(0xFF38BDF8);
        break;
      case AssemblyPartType.channel:
        typeIcon = Icons.view_sidebar_rounded;
        typeColor = const Color(0xFF64748B);
        break;
      case AssemblyPartType.angle:
        typeIcon = Icons.square_foot_rounded;
        typeColor = const Color(0xFF475569);
        break;
      case AssemblyPartType.rod:
        typeIcon = Icons.circle_outlined;
        typeColor = const Color(0xFF0D9488);
        break;
      case AssemblyPartType.bar:
        typeIcon = Icons.horizontal_rule_rounded;
        typeColor = const Color(0xFF6366F1);
        break;
      case AssemblyPartType.iBeam:
        typeIcon = Icons.view_headline_rounded;
        typeColor = const Color(0xFF1E293B);
        break;
      case AssemblyPartType.straightRail:
        typeIcon = Icons.view_column_rounded;
        typeColor = const Color(0xFF34D399);
        break;
      case AssemblyPartType.bentRail:
        typeIcon = Icons.alt_route_rounded;
        typeColor = const Color(0xFFFBBF24);
        break;
      case AssemblyPartType.walkThroughStile:
        typeIcon = Icons.arrow_upward_rounded;
        typeColor = const Color(0xFF38BDF8);
        break;
      case AssemblyPartType.boxTubeStile:
        typeIcon = Icons.crop_square_rounded;
        typeColor = const Color(0xFF64748B);
        break;
      case AssemblyPartType.diamondGripRung:
        typeIcon = Icons.grid_on_rounded;
        typeColor = const Color(0xFF10B981);
        break;
      case AssemblyPartType.wideStepTread:
        typeIcon = Icons.horizontal_split_rounded;
        typeColor = const Color(0xFF059669);
        break;
      case AssemblyPartType.safetyCageHoop:
      case AssemblyPartType.safetyCageBellHoop:
        typeIcon = Icons.lens_blur_rounded;
        typeColor = const Color(0xFFF59E0B);
        break;
      case AssemblyPartType.cageStrap:
        typeIcon = Icons.vertical_distribute_rounded;
        typeColor = const Color(0xFFD97706);
        break;
      case AssemblyPartType.standoffBracket:
        typeIcon = Icons.hardware_rounded;
        typeColor = const Color(0xFF64748B);
        break;
      case AssemblyPartType.baseFootPlate:
        typeIcon = Icons.file_download_done_rounded;
        typeColor = const Color(0xFF475569);
        break;
      case AssemblyPartType.splicePlate:
        typeIcon = Icons.join_inner_rounded;
        typeColor = const Color(0xFF94A3B8);
        break;
      case AssemblyPartType.swingGate:
        typeIcon = Icons.meeting_room_rounded;
        typeColor = const Color(0xFFEAB308);
        break;
      case AssemblyPartType.customExtrusion:
        typeIcon = Icons.layers_rounded;
        typeColor = const Color(0xFF6366F1);
        break;
      case AssemblyPartType.cableTrayStraight:
      case AssemblyPartType.cableTrayBend90:
      case AssemblyPartType.cableTrayBend45:
      case AssemblyPartType.cableTrayInsideRiser:
      case AssemblyPartType.cableTrayOutsideRiser:
      case AssemblyPartType.cableTrayTee:
      case AssemblyPartType.cableTrayCross:
      case AssemblyPartType.cableTrayReducer:
      case AssemblyPartType.cableTrayCoupler:
      case AssemblyPartType.holdDownClamp:
        typeIcon = Icons.dashboard_outlined;
        typeColor = const Color(0xFF0284C7);
        break;
      case AssemblyPartType.cableTrunkingBody:
      case AssemblyPartType.cableTrunkingCover:
      case AssemblyPartType.cableTrunkingBend:
      case AssemblyPartType.cableTrunkingRiser:
      case AssemblyPartType.cableTrunkingTee:
      case AssemblyPartType.cableTrunkingCoupler:
        typeIcon = Icons.view_stream_rounded;
        typeColor = const Color(0xFF0D9488);
        break;
      case AssemblyPartType.customSheetMetal:
        typeIcon = Icons.architecture_rounded;
        typeColor = const Color(0xFF38BDF8);
        break;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFE0F2FE) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isSelected ? const Color(0xFF0284C7) : const Color(0xFFE2E8F0),
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        leading: Icon(typeIcon, color: typeColor, size: 16),
        title: Text(
          part.name,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? const Color(0xFF0369A1) : const Color(0xFF0F172A),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: [
            Text(
              '${part.length.toInt()}mm • F:${part.flangeWidth.toInt()}mm',
              style: const TextStyle(fontSize: 9, color: Color(0xFF64748B)),
            ),
            if (weldCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.flash_on_rounded, size: 8, color: Color(0xFFF59E0B)),
                    Text(
                      '$weldCount',
                      style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Color(0xFFF59E0B)),
                    ),
                  ],
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () {
                viewModel.selectPart(part.id);
                viewModel.duplicateSelectedPart();
              },
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.copy_rounded, size: 14, color: Color(0xFF64748B)),
              ),
            ),
            const SizedBox(width: 2),
            InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () {
                viewModel.selectPart(part.id);
                viewModel.deleteSelectedPart();
              },
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close_rounded, size: 14, color: Color(0xFFEF4444)),
              ),
            ),
          ],
        ),
        onTap: () {
          viewModel.selectPart(part.id);
        },
      ),
    );
  }
}

/// Miniature CAD preview thumbnail widget displaying an authentic technical cross-section
/// and 3D profile of the specified assembly part type.
class _PartMiniatureThumbnail extends StatelessWidget {
  final AssemblyPartType partType;
  final Color accentColor;
  final double size;

  const _PartMiniatureThumbnail({
    required this.partType,
    required this.accentColor,
    this.size = 36.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 1.0),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        size: Size(size, size),
        painter: _PartMiniaturePainter(
          partType: partType,
          accentColor: accentColor,
        ),
      ),
    );
  }
}

/// CustomPainter rendering crisp, authentic CAD isometric diagrams of the 8 modular assembly parts.
class _PartMiniaturePainter extends CustomPainter {
  final AssemblyPartType partType;
  final Color accentColor;

  const _PartMiniaturePainter({
    required this.partType,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final fillPaint = Paint()..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xFF334155);
    final holePaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF0F172A);

    switch (partType) {
      case AssemblyPartType.rung:
        // Slotted C-Rung (40x20): Top web with punched obround cable-tie slots, facing down flanges
        final topPath = Path()
          ..moveTo(w * 0.20, h * 0.36)
          ..lineTo(w * 0.65, h * 0.20)
          ..lineTo(w * 0.85, h * 0.32)
          ..lineTo(w * 0.38, h * 0.48)
          ..close();
        fillPaint.color = const Color(0xFFE2E8F0);
        canvas.drawPath(topPath, fillPaint);
        canvas.drawPath(topPath, strokePaint);

        // Front flange face
        final frontPath = Path()
          ..moveTo(w * 0.38, h * 0.48)
          ..lineTo(w * 0.85, h * 0.32)
          ..lineTo(w * 0.85, h * 0.62)
          ..lineTo(w * 0.38, h * 0.78)
          ..close();
        fillPaint.color = const Color(0xFFCBD5E1);
        canvas.drawPath(frontPath, fillPaint);
        canvas.drawPath(frontPath, strokePaint);

        // Left return lip
        final leftPath = Path()
          ..moveTo(w * 0.20, h * 0.36)
          ..lineTo(w * 0.38, h * 0.48)
          ..lineTo(w * 0.38, h * 0.78)
          ..lineTo(w * 0.20, h * 0.66)
          ..close();
        fillPaint.color = const Color(0xFF94A3B8);
        canvas.drawPath(leftPath, fillPaint);
        canvas.drawPath(leftPath, strokePaint);

        // 2 Miniature obround slots on the top surface
        canvas.save();
        canvas.translate(w * 0.46, h * 0.33);
        canvas.rotate(-0.35);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: w * 0.16, height: h * 0.07),
            Radius.circular(h * 0.035),
          ),
          holePaint,
        );
        canvas.restore();

        canvas.save();
        canvas.translate(w * 0.64, h * 0.26);
        canvas.rotate(-0.35);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: w * 0.16, height: h * 0.07),
            Radius.circular(h * 0.035),
          ),
          holePaint,
        );
        canvas.restore();
        break;

      case AssemblyPartType.straightRail:
        // Straight C-Rail with punched rung slots along web
        final webPath = Path()
          ..moveTo(w * 0.24, h * 0.18)
          ..lineTo(w * 0.58, h * 0.14)
          ..lineTo(w * 0.58, h * 0.84)
          ..lineTo(w * 0.24, h * 0.88)
          ..close();
        fillPaint.color = const Color(0xFFE2E8F0);
        canvas.drawPath(webPath, fillPaint);
        canvas.drawPath(webPath, strokePaint);

        // Top flange
        final topFlange = Path()
          ..moveTo(w * 0.24, h * 0.18)
          ..lineTo(w * 0.42, h * 0.25)
          ..lineTo(w * 0.76, h * 0.21)
          ..lineTo(w * 0.58, h * 0.14)
          ..close();
        fillPaint.color = const Color(0xFFF8FAFC);
        canvas.drawPath(topFlange, fillPaint);
        canvas.drawPath(topFlange, strokePaint);

        // Bottom flange
        final btmFlange = Path()
          ..moveTo(w * 0.24, h * 0.88)
          ..lineTo(w * 0.42, h * 0.95)
          ..lineTo(w * 0.76, h * 0.91)
          ..lineTo(w * 0.58, h * 0.84)
          ..close();
        fillPaint.color = const Color(0xFF94A3B8);
        canvas.drawPath(btmFlange, fillPaint);
        canvas.drawPath(btmFlange, strokePaint);

        // 3 Punch slots along the web
        for (final dy in [0.35, 0.52, 0.69]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset(w * 0.40, h * dy), width: w * 0.18, height: h * 0.075),
              Radius.circular(h * 0.035),
            ),
            holePaint,
          );
        }
        break;

      case AssemblyPartType.bentRail:
        // Bent / Swaged rail showing swan-neck offset
        final bentPath = Path()
          ..moveTo(w * 0.22, h * 0.86)
          ..lineTo(w * 0.44, h * 0.76)
          ..lineTo(w * 0.56, h * 0.48)
          ..lineTo(w * 0.78, h * 0.22)
          ..lineTo(w * 0.86, h * 0.25)
          ..lineTo(w * 0.64, h * 0.52)
          ..lineTo(w * 0.52, h * 0.80)
          ..lineTo(w * 0.28, h * 0.92)
          ..close();
        fillPaint.color = const Color(0xFFCBD5E1);
        canvas.drawPath(bentPath, fillPaint);
        canvas.drawPath(bentPath, strokePaint);

        // Highlight bend lines in amber
        final amberStroke = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = const Color(0xFFF59E0B);
        canvas.drawLine(Offset(w * 0.44, h * 0.76), Offset(w * 0.52, h * 0.80), amberStroke);
        canvas.drawLine(Offset(w * 0.56, h * 0.48), Offset(w * 0.64, h * 0.52), amberStroke);
        break;

      case AssemblyPartType.channel:
        // Structural C-Channel
        final cPath = Path()
          ..moveTo(w * 0.22, h * 0.20)
          ..lineTo(w * 0.70, h * 0.16)
          ..lineTo(w * 0.70, h * 0.28)
          ..lineTo(w * 0.36, h * 0.30)
          ..lineTo(w * 0.36, h * 0.70)
          ..lineTo(w * 0.70, h * 0.68)
          ..lineTo(w * 0.70, h * 0.80)
          ..lineTo(w * 0.22, h * 0.80)
          ..close();
        fillPaint.color = const Color(0xFFE2E8F0);
        canvas.drawPath(cPath, fillPaint);
        canvas.drawPath(cPath, strokePaint);

        // Extruded 3D depth lines
        canvas.drawLine(Offset(w * 0.70, h * 0.16), Offset(w * 0.84, h * 0.26), strokePaint);
        canvas.drawLine(Offset(w * 0.70, h * 0.80), Offset(w * 0.84, h * 0.90), strokePaint);
        canvas.drawLine(Offset(w * 0.84, h * 0.26), Offset(w * 0.84, h * 0.90), strokePaint);
        break;

      case AssemblyPartType.angle:
        // Equal Leg L-Angle Iron (90° corner)
        final lPath = Path()
          ..moveTo(w * 0.24, h * 0.18)
          ..lineTo(w * 0.38, h * 0.18)
          ..lineTo(w * 0.38, h * 0.68)
          ..lineTo(w * 0.78, h * 0.68)
          ..lineTo(w * 0.78, h * 0.82)
          ..lineTo(w * 0.24, h * 0.82)
          ..close();
        fillPaint.color = const Color(0xFFE2E8F0);
        canvas.drawPath(lPath, fillPaint);
        canvas.drawPath(lPath, strokePaint);

        // 3D depth extrusion
        canvas.drawLine(Offset(w * 0.38, h * 0.18), Offset(w * 0.52, h * 0.26), strokePaint);
        canvas.drawLine(Offset(w * 0.78, h * 0.68), Offset(w * 0.90, h * 0.76), strokePaint);
        canvas.drawLine(Offset(w * 0.78, h * 0.82), Offset(w * 0.90, h * 0.90), strokePaint);
        canvas.drawLine(Offset(w * 0.90, h * 0.76), Offset(w * 0.90, h * 0.90), strokePaint);
        break;

      case AssemblyPartType.rod:
        // Solid Round Rod / Bar (Cylinder)
        final rodPath = Path()
          ..moveTo(w * 0.20, h * 0.62)
          ..lineTo(w * 0.60, h * 0.22)
          ..arcToPoint(Offset(w * 0.82, h * 0.44), radius: Radius.circular(w * 0.15))
          ..lineTo(w * 0.42, h * 0.84)
          ..arcToPoint(Offset(w * 0.20, h * 0.62), radius: Radius.circular(w * 0.15))
          ..close();
        fillPaint.color = const Color(0xFFCBD5E1);
        canvas.drawPath(rodPath, fillPaint);
        canvas.drawPath(rodPath, strokePaint);

        // Front end face ellipse
        canvas.drawOval(
          Rect.fromCenter(center: Offset(w * 0.31, h * 0.73), width: w * 0.28, height: h * 0.18),
          Paint()..color = const Color(0xFFE2E8F0)..style = PaintingStyle.fill,
        );
        canvas.drawOval(
          Rect.fromCenter(center: Offset(w * 0.31, h * 0.73), width: w * 0.28, height: h * 0.18),
          strokePaint,
        );
        break;

      case AssemblyPartType.bar:
        // Rectangular Flat Solid Bar
        final topFace = Path()
          ..moveTo(w * 0.20, h * 0.46)
          ..lineTo(w * 0.58, h * 0.22)
          ..lineTo(w * 0.82, h * 0.32)
          ..lineTo(w * 0.44, h * 0.56)
          ..close();
        fillPaint.color = const Color(0xFFE2E8F0);
        canvas.drawPath(topFace, fillPaint);
        canvas.drawPath(topFace, strokePaint);

        final sideFace = Path()
          ..moveTo(w * 0.44, h * 0.56)
          ..lineTo(w * 0.82, h * 0.32)
          ..lineTo(w * 0.82, h * 0.44)
          ..lineTo(w * 0.44, h * 0.68)
          ..close();
        fillPaint.color = const Color(0xFF94A3B8);
        canvas.drawPath(sideFace, fillPaint);
        canvas.drawPath(sideFace, strokePaint);

        final frontFace = Path()
          ..moveTo(w * 0.20, h * 0.46)
          ..lineTo(w * 0.44, h * 0.56)
          ..lineTo(w * 0.44, h * 0.68)
          ..lineTo(w * 0.20, h * 0.58)
          ..close();
        fillPaint.color = const Color(0xFFCBD5E1);
        canvas.drawPath(frontFace, fillPaint);
        canvas.drawPath(frontFace, strokePaint);
        break;

      case AssemblyPartType.iBeam:
        // Structural I-Beam (H-Beam)
        final topFlange = Path()
          ..moveTo(w * 0.20, h * 0.20)
          ..lineTo(w * 0.68, h * 0.16)
          ..lineTo(w * 0.80, h * 0.26)
          ..lineTo(w * 0.32, h * 0.30)
          ..close();
        fillPaint.color = const Color(0xFFF1F5F9);
        canvas.drawPath(topFlange, fillPaint);
        canvas.drawPath(topFlange, strokePaint);

        // Web face
        final webFace = Path()
          ..moveTo(w * 0.50, h * 0.23)
          ..lineTo(w * 0.56, h * 0.28)
          ..lineTo(w * 0.56, h * 0.70)
          ..lineTo(w * 0.50, h * 0.65)
          ..close();
        fillPaint.color = const Color(0xFF64748B);
        canvas.drawPath(webFace, fillPaint);
        canvas.drawPath(webFace, strokePaint);

        // Bottom flange
        final btmFlange = Path()
          ..moveTo(w * 0.20, h * 0.72)
          ..lineTo(w * 0.68, h * 0.68)
          ..lineTo(w * 0.80, h * 0.78)
          ..lineTo(w * 0.32, h * 0.82)
          ..close();
        fillPaint.color = const Color(0xFFCBD5E1);
        canvas.drawPath(btmFlange, fillPaint);
        canvas.drawPath(btmFlange, strokePaint);
        break;

      case AssemblyPartType.walkThroughStile:
        // Arched walk-through stile with flared top
        final stilePath = Path()
          ..moveTo(w * 0.35, h * 0.85)
          ..lineTo(w * 0.35, h * 0.35)
          ..quadraticBezierTo(w * 0.35, h * 0.15, w * 0.65, h * 0.15)
          ..lineTo(w * 0.75, h * 0.35)
          ..lineTo(w * 0.65, h * 0.35)
          ..quadraticBezierTo(w * 0.45, h * 0.22, w * 0.45, h * 0.40)
          ..lineTo(w * 0.45, h * 0.85)
          ..close();
        fillPaint.color = const Color(0xFF38BDF8);
        canvas.drawPath(stilePath, fillPaint);
        canvas.drawPath(stilePath, strokePaint);
        break;

      case AssemblyPartType.boxTubeStile:
        // Hollow rectangular tube
        final outerRect = Rect.fromCenter(center: Offset(w * 0.5, h * 0.5), width: w * 0.5, height: h * 0.6);
        final innerRect = Rect.fromCenter(center: Offset(w * 0.5, h * 0.5), width: w * 0.35, height: h * 0.45);
        fillPaint.color = const Color(0xFF94A3B8);
        canvas.drawRect(outerRect, fillPaint);
        canvas.drawRect(outerRect, strokePaint);
        canvas.drawRect(innerRect, holePaint);
        break;

      case AssemblyPartType.diamondGripRung:
        // C-rung with diamond perforation icons
        final rungRect = Rect.fromCenter(center: Offset(w * 0.5, h * 0.5), width: w * 0.7, height: h * 0.35);
        fillPaint.color = const Color(0xFFCBD5E1);
        canvas.drawRect(rungRect, fillPaint);
        canvas.drawRect(rungRect, strokePaint);
        for (final dx in [-0.2, 0.0, 0.2]) {
          final diamond = Path()
            ..moveTo(w * (0.5 + dx), h * 0.44)
            ..lineTo(w * (0.5 + dx + 0.05), h * 0.50)
            ..lineTo(w * (0.5 + dx), h * 0.56)
            ..lineTo(w * (0.5 + dx - 0.05), h * 0.50)
            ..close();
          canvas.drawPath(diamond, holePaint);
        }
        break;

      case AssemblyPartType.wideStepTread:
        // Deep step tread with ribbed traction
        final treadPath = Path()
          ..moveTo(w * 0.15, h * 0.45)
          ..lineTo(w * 0.85, h * 0.35)
          ..lineTo(w * 0.85, h * 0.65)
          ..lineTo(w * 0.15, h * 0.75)
          ..close();
        fillPaint.color = const Color(0xFF94A3B8);
        canvas.drawPath(treadPath, fillPaint);
        canvas.drawPath(treadPath, strokePaint);
        break;

      case AssemblyPartType.safetyCageHoop:
      case AssemblyPartType.safetyCageBellHoop:
        // Circular horseshoe hoop
        final hoopPath = Path()
          ..moveTo(w * 0.20, h * 0.75)
          ..lineTo(w * 0.20, h * 0.50)
          ..arcToPoint(Offset(w * 0.80, h * 0.50), radius: Radius.circular(w * 0.30))
          ..lineTo(w * 0.80, h * 0.75);
        final hoopStroke = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = partType == AssemblyPartType.safetyCageBellHoop ? 4.5 : 3.5
          ..color = partType == AssemblyPartType.safetyCageBellHoop ? const Color(0xFFF59E0B) : const Color(0xFF64748B);
        canvas.drawPath(hoopPath, hoopStroke);
        break;

      case AssemblyPartType.cageStrap:
        // Vertical flat bar strap
        final strapRect = Rect.fromCenter(center: Offset(w * 0.5, h * 0.5), width: w * 0.18, height: h * 0.75);
        fillPaint.color = const Color(0xFF94A3B8);
        canvas.drawRect(strapRect, fillPaint);
        canvas.drawRect(strapRect, strokePaint);
        break;

      case AssemblyPartType.standoffBracket:
        // Angle standoff bracket
        final armPath = Path()
          ..moveTo(w * 0.25, h * 0.70)
          ..lineTo(w * 0.70, h * 0.70)
          ..lineTo(w * 0.70, h * 0.35)
          ..lineTo(w * 0.80, h * 0.35)
          ..lineTo(w * 0.80, h * 0.80)
          ..lineTo(w * 0.25, h * 0.80)
          ..close();
        fillPaint.color = const Color(0xFF64748B);
        canvas.drawPath(armPath, fillPaint);
        canvas.drawPath(armPath, strokePaint);
        break;

      case AssemblyPartType.baseFootPlate:
        // Base shoe plate with anchor holes
        final plateRect = Rect.fromCenter(center: Offset(w * 0.5, h * 0.70), width: w * 0.7, height: h * 0.20);
        final cleatRect = Rect.fromCenter(center: Offset(w * 0.5, h * 0.45), width: w * 0.25, height: h * 0.35);
        fillPaint.color = const Color(0xFF475569);
        canvas.drawRect(plateRect, fillPaint);
        canvas.drawRect(plateRect, strokePaint);
        canvas.drawRect(cleatRect, fillPaint);
        canvas.drawRect(cleatRect, strokePaint);
        break;

      case AssemblyPartType.splicePlate:
        // Splice fishplate with 4 holes
        final fishplate = Rect.fromCenter(center: Offset(w * 0.5, h * 0.5), width: w * 0.35, height: h * 0.75);
        fillPaint.color = const Color(0xFF94A3B8);
        canvas.drawRect(fishplate, fillPaint);
        canvas.drawRect(fishplate, strokePaint);
        for (final dy in [-0.22, -0.07, 0.07, 0.22]) {
          canvas.drawCircle(Offset(w * 0.5, h * (0.5 + dy)), 2.5, holePaint);
        }
        break;

      case AssemblyPartType.swingGate:
        // Gate frame with yellow bars
        final gateBorder = Rect.fromCenter(center: Offset(w * 0.5, h * 0.5), width: w * 0.65, height: h * 0.55);
        fillPaint.color = const Color(0xFFFBBF24);
        final gateStroke = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0
          ..color = const Color(0xFFFBBF24);
        canvas.drawRect(gateBorder, gateStroke);
        canvas.drawLine(Offset(w * 0.18, h * 0.5), Offset(w * 0.82, h * 0.5), gateStroke);
        break;

      case AssemblyPartType.customExtrusion:
        final box = Rect.fromCenter(center: Offset(w * 0.5, h * 0.5), width: w * 0.6, height: h * 0.6);
        fillPaint.color = const Color(0xFF6366F1);
        canvas.drawRect(box, fillPaint);
        canvas.drawRect(box, strokePaint);
        break;

      case AssemblyPartType.cableTrayStraight:
      case AssemblyPartType.cableTrayBend90:
      case AssemblyPartType.cableTrayBend45:
      case AssemblyPartType.cableTrayInsideRiser:
      case AssemblyPartType.cableTrayOutsideRiser:
      case AssemblyPartType.cableTrayTee:
      case AssemblyPartType.cableTrayCross:
      case AssemblyPartType.cableTrayReducer:
      case AssemblyPartType.cableTrayCoupler:
      case AssemblyPartType.holdDownClamp:
      case AssemblyPartType.cableTrunkingBody:
      case AssemblyPartType.cableTrunkingCover:
      case AssemblyPartType.cableTrunkingBend:
      case AssemblyPartType.cableTrunkingRiser:
      case AssemblyPartType.cableTrunkingTee:
      case AssemblyPartType.cableTrunkingCoupler:
      case AssemblyPartType.customSheetMetal:
        final trayBox = Rect.fromCenter(center: Offset(w * 0.5, h * 0.5), width: w * 0.7, height: h * 0.45);
        fillPaint.color = const Color(0xFF64748B);
        canvas.drawRect(trayBox, fillPaint);
        canvas.drawRect(trayBox, strokePaint);
        for (final dx in [-0.2, 0.0, 0.2]) {
          canvas.drawCircle(Offset(w * (0.5 + dx), h * 0.5), 2.2, holePaint);
        }
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _PartMiniaturePainter oldDelegate) =>
      oldDelegate.partType != partType || oldDelegate.accentColor != accentColor;
}
