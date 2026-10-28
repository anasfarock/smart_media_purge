import 'package:flutter/material.dart';

import '../duplicates/duplicates_screen.dart';
import '../faces/faces_screen.dart';
import '../ocr/ocr_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Smart Media Purge')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Storage optimizer', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'Everything runs on this device. No photo, text or face data is ever uploaded.',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          _ModuleCard(
            icon: Icons.content_copy_rounded,
            title: 'Visual duplicates',
            subtitle: 'Find exact and near-identical photos and keep the best copy.',
            builder: (_) => const DuplicatesScreen(),
          ),
          _ModuleCard(
            icon: Icons.document_scanner_rounded,
            title: 'Document parsing (OCR)',
            subtitle: 'Index receipts, notes and IDs, search offline, flag sensitive data.',
            builder: (_) => const OcrScreen(),
          ),
          _ModuleCard(
            icon: Icons.face_retouching_natural_rounded,
            title: 'People',
            subtitle: 'Group photos by person, hide or lock the ones you want private.',
            builder: (_) => const FacesScreen(),
          ),
        ],
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.builder,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: builder)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: cs.primaryContainer,
                child: Icon(icon, color: cs.onPrimaryContainer),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
