import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import 'duplicate_controller.dart';
import 'duplicate_models.dart';

class DuplicatesScreen extends StatelessWidget {
  const DuplicatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<DuplicateController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Visual duplicates'),
        actions: [
          IconButton(
            tooltip: 'Sensitivity',
            icon: const Icon(Icons.tune),
            onPressed: c.status == ScanStatus.scanning
                ? null
                : () => _showSettings(context),
          ),
        ],
      ),
      body: _body(context, c),
      bottomNavigationBar: c.status == ScanStatus.done && c.groups.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: c.selected.isEmpty ? null : () => _confirmDelete(context, c),
                  label: Text(
                      'Delete ${c.selected.length} selected - free ${formatBytes(c.reclaimableBytes)}'),
                ),
              ),
            )
          : null,
    );
  }

  Widget _body(BuildContext context, DuplicateController c) {
    switch (c.status) {
      case ScanStatus.idle:
        return _Centered(
          icon: Icons.content_copy_rounded,
          title: 'Scan your gallery',
          text: c.usingNeuralEmbeddings
              ? 'Uses an on-device neural network plus hashing. Nothing leaves your phone.'
              : 'Neural model not found - using perceptual hashing only (see README).',
          action: FilledButton(onPressed: c.scan, child: const Text('Start scan')),
        );
      case ScanStatus.scanning:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: c.progress),
                const SizedBox(height: 12),
                Text(c.message),
              ],
            ),
          ),
        );
      case ScanStatus.permissionDenied:
        return const _Centered(
          icon: Icons.lock_outline,
          title: 'Photo access needed',
          text: 'Grant full photo access so duplicates can be found.',
          action: FilledButton(
              onPressed: PhotoManager.openSetting, child: Text('Open settings')),
        );
      case ScanStatus.error:
        return _Centered(
          icon: Icons.error_outline,
          title: 'Scan failed',
          text: c.error ?? 'Unknown error',
          action: FilledButton(onPressed: c.scan, child: const Text('Retry')),
        );
      case ScanStatus.done:
        if (c.groups.isEmpty) {
          return _Centered(
            icon: Icons.check_circle_outline,
            title: 'No duplicates found',
            text: 'Try raising the sensitivity.',
            action: FilledButton(onPressed: c.scan, child: const Text('Scan again')),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: c.groups.length,
          itemBuilder: (_, i) => _GroupCard(group: c.groups[i]),
        );
    }
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => Consumer<DuplicateController>(
        builder: (_, c, __) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Match sensitivity', style: Theme.of(context).textTheme.titleMedium),
              Slider(value: c.sensitivity, onChanged: c.setSensitivity),
              const Text('Low = only near-identical shots. High = also groups bursts and edits.'),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  c.scan();
                },
                child: const Text('Re-scan'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, DuplicateController c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete selected photos?'),
        content: Text(
            '${c.selected.length} photos (${formatBytes(c.reclaimableBytes)}) will be removed. '
            'Android will ask you to confirm.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    final n = await c.deleteSelected();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Deleted $n photos')));
    }
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group});
  final DuplicateGroup group;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<DuplicateController>();
    final cs = Theme.of(context).colorScheme;
    final reclaim = group.items
        .where((i) => c.selected.contains(i.asset.id))
        .fold<int>(0, (s, i) => s + i.fp.sizeBytes);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Chip(
                    label: Text(group.exact ? 'Exact copies' : 'Similar'),
                    backgroundColor:
                        group.exact ? cs.errorContainer : cs.secondaryContainer,
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 8),
                  Text('${group.items.length} files'),
                  const Spacer(),
                  Text('free ${formatBytes(reclaim)}',
                      style: TextStyle(color: cs.primary)),
                ],
              ),
            ),
            SizedBox(
              height: 190,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: group.items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => _Tile(group: group, item: group.items[i], isKeeper: i == 0),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.group, required this.item, required this.isKeeper});
  final DuplicateGroup group;
  final DuplicateItem item;
  final bool isKeeper;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<DuplicateController>();
    final cs = Theme.of(context).colorScheme;
    final marked = c.selected.contains(item.asset.id);
    return GestureDetector(
      onTap: () {
        if (!c.toggle(group, item.asset.id)) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Keep at least one photo in each group')));
        }
      },
      child: SizedBox(
        width: 130,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: AssetEntityImage(
                      item.asset,
                      isOriginal: false,
                      thumbnailSize: const ThumbnailSize.square(300),
                      fit: BoxFit.cover,
                    ),
                  ),
                  if (marked)
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: Colors.black.withValues(alpha: 0.45),
                      ),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                  if (isKeeper)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: cs.primary, borderRadius: BorderRadius.circular(6)),
                        child: Text('BEST',
                            style: TextStyle(
                                color: cs.onPrimary,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(item.description, style: const TextStyle(fontSize: 12)),
            Text(formatBytes(item.fp.sizeBytes),
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.icon, required this.title, required this.text, this.action});
  final IconData icon;
  final String title;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(text, textAlign: TextAlign.center),
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      );
}
