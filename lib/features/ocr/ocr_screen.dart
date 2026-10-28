import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:provider/provider.dart';

import '../duplicates/duplicate_controller.dart' show ScanStatus;
import 'ocr_controller.dart';
import 'ocr_models.dart';
import 'sensitive_detector.dart';

class OcrScreen extends StatefulWidget {
  const OcrScreen({super.key});

  @override
  State<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends State<OcrScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<OcrController>().refresh());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<OcrController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Documents'),
        actions: [
          IconButton(
            tooltip: 'Build tax-ready folders',
            icon: const Icon(Icons.folder_special_outlined),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final r = await c.buildTaxFolders();
              messenger.showSnackBar(SnackBar(
                  content: Text('${r.fileCount} files organised in ${r.root}')));
            },
          ),
        ],
      ),
      floatingActionButton: c.status == ScanStatus.scanning
          ? null
          : FloatingActionButton.extended(
              onPressed: c.scan,
              icon: const Icon(Icons.document_scanner),
              label: const Text('Scan'),
            ),
      body: Column(
        children: [
          if (c.status == ScanStatus.scanning)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                LinearProgressIndicator(value: c.progress),
                const SizedBox(height: 4),
                Text(c.message),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SearchBar(
              hintText: 'Search text in receipts, notes, IDs...',
              leading: const Icon(Icons.search),
              onChanged: c.setQuery,
            ),
          ),
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _chip(c, null, 'All'),
                for (final t in DocType.values)
                  _chip(c, t, '${t.label} ${c.counts[t] ?? 0}'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Text('Scan scope:'),
                const SizedBox(width: 8),
                SegmentedButton<OcrScope>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: OcrScope.likelyDocuments, label: Text('Doc folders')),
                    ButtonSegment(value: OcrScope.everything, label: Text('Everything')),
                  ],
                  selected: {c.scope},
                  onSelectionChanged: (s) => c.setScope(s.first),
                ),
              ],
            ),
          ),
          Expanded(
            child: c.results.isEmpty
                ? const Center(child: Text('No documents yet - tap Scan.'))
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: c.results.length,
                    itemBuilder: (_, i) => _DocTile(doc: c.results[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chip(OcrController c, DocType? t, String label) => Padding(
        padding: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
        child: FilterChip(
          label: Text(label),
          selected: c.filter == t,
          onSelected: (_) => c.setFilter(t),
        ),
      );
}

class _DocTile extends StatelessWidget {
  const _DocTile({required this.doc});
  final DocumentRecord doc;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = doc.merchant ?? doc.type.label;
    final sub = [
      doc.type.label,
      if (doc.amount != null) doc.amount!.toStringAsFixed(2),
      if (doc.date != null) DateFormat.yMMMd().format(doc.date!),
    ].join(' - ');
    return ListTile(
      leading: SizedBox(width: 56, height: 56, child: _AssetThumb(assetId: doc.assetId)),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(sub),
      trailing: doc.sensitiveCount > 0
          ? Tooltip(
              message: '${doc.sensitiveCount} sensitive item(s)',
              child: Icon(Icons.shield_outlined, color: cs.error),
            )
          : null,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DocumentDetailScreen(doc: doc)),
      ),
    );
  }
}

class _AssetThumb extends StatelessWidget {
  const _AssetThumb({required this.assetId});
  final String assetId;

  @override
  Widget build(BuildContext context) => FutureBuilder<AssetEntity?>(
        future: AssetEntity.fromId(assetId),
        builder: (_, snap) {
          final a = snap.data;
          if (a == null) return const ColoredBox(color: Colors.black12);
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AssetEntityImage(a,
                isOriginal: false,
                thumbnailSize: const ThumbnailSize.square(160),
                fit: BoxFit.cover),
          );
        },
      );
}

class DocumentDetailScreen extends StatelessWidget {
  const DocumentDetailScreen({super.key, required this.doc});
  final DocumentRecord doc;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final matches = SensitiveDetector.scan(doc.body);
    return Scaffold(
      appBar: AppBar(title: Text(doc.merchant ?? doc.type.label)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SizedBox(height: 220, child: _AssetThumb(assetId: doc.assetId)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              Chip(label: Text(doc.type.label)),
              if (doc.amount != null) Chip(label: Text('Total ${doc.amount!.toStringAsFixed(2)}')),
              if (doc.date != null) Chip(label: Text(DateFormat.yMMMd().format(doc.date!))),
            ],
          ),
          if (matches.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: cs.errorContainer, borderRadius: BorderRadius.circular(12)),
              child: Text(
                'Contains: ${matches.map((m) => m.type.label).toSet().join(', ')}. '
                'Think twice before sharing this image.',
                style: TextStyle(color: cs.onErrorContainer),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text('Extracted text', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SelectableText.rich(TextSpan(children: _spans(doc.body, matches, cs))),
        ],
      ),
    );
  }

  List<TextSpan> _spans(String text, List<SensitiveMatch> matches, ColorScheme cs) {
    final spans = <TextSpan>[];
    var pos = 0;
    for (final m in matches) {
      if (m.start > pos) spans.add(TextSpan(text: text.substring(pos, m.start)));
      spans.add(TextSpan(
        text: text.substring(m.start, m.end),
        style: TextStyle(
          backgroundColor: cs.errorContainer,
          color: cs.onErrorContainer,
          fontWeight: FontWeight.bold,
        ),
      ));
      pos = m.end;
    }
    if (pos < text.length) spans.add(TextSpan(text: text.substring(pos)));
    return spans;
  }
}
