import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:provider/provider.dart';

import '../duplicates/duplicate_controller.dart' show ScanStatus;
import 'face_controller.dart';
import 'face_models.dart';
import 'vault_gate.dart';

class FacesScreen extends StatefulWidget {
  const FacesScreen({super.key});

  @override
  State<FacesScreen> createState() => _FacesScreenState();
}

class _FacesScreenState extends State<FacesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<FaceController>().load());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<FaceController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('People'),
        actions: [
          IconButton(
            tooltip: 'Match strictness',
            icon: const Icon(Icons.tune),
            onPressed: () => _settings(context),
          ),
          IconButton(
            tooltip: 'Hidden people',
            icon: const Icon(Icons.visibility_off_outlined),
            onPressed: () async {
              if (await ensureUnlocked(context) && context.mounted) {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _HiddenScreen()));
              }
            },
          ),
        ],
      ),
      floatingActionButton: c.status == ScanStatus.scanning
          ? null
          : FloatingActionButton.extended(
              onPressed: c.scan,
              icon: const Icon(Icons.face),
              label: const Text('Scan faces'),
            ),
      body: Column(
        children: [
          if (!c.modelReady)
            const MaterialBanner(
              content: Text('Face model missing: add assets/models/mobilefacenet.tflite (see README).'),
              actions: [SizedBox.shrink()],
            ),
          if (c.status == ScanStatus.scanning)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [LinearProgressIndicator(value: c.progress), Text(c.message)]),
            ),
          if (c.status == ScanStatus.error && c.error != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(c.error!)),
          Expanded(
            child: c.visible.isEmpty
                ? const Center(child: Text('No people yet - tap "Scan faces".'))
                : _PeopleGrid(people: c.visible),
          ),
        ],
      ),
    );
  }

  void _settings(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => Consumer<FaceController>(
        builder: (_, c, __) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Match strictness: ${c.strictness.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.titleMedium),
            Slider(min: 0.35, max: 0.8, value: c.strictness, onChanged: c.setStrictness),
            const Text('Higher = fewer wrong merges but more duplicate people. '
                'Applies the next time you scan.'),
          ]),
        ),
      ),
    );
  }
}

class _PeopleGrid extends StatelessWidget {
  const _PeopleGrid({required this.people, this.showUnlockedAlways = false});
  final List<PersonCluster> people;
  final bool showUnlockedAlways;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, mainAxisSpacing: 16, crossAxisSpacing: 8, childAspectRatio: 0.78),
      itemCount: people.length,
      itemBuilder: (_, i) => _PersonTile(person: people[i], bypassLock: showUnlockedAlways),
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({required this.person, required this.bypassLock});
  final PersonCluster person;
  final bool bypassLock;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        if (person.locked && !bypassLock && !await ensureUnlocked(context)) return;
        if (!context.mounted) return;
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => PersonDetailScreen(person: person)));
      },
      onLongPress: () => _menu(context),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              CircleAvatar(
                radius: 44,
                backgroundColor: cs.surfaceContainerHighest,
                backgroundImage:
                    (person.locked || person.thumb == null) ? null : MemoryImage(person.thumb!),
                child: person.locked ? const Icon(Icons.lock, size: 32) : null,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(person.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('${person.photoCount} photos',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  void _menu(BuildContext context) {
    final c = context.read<FaceController>();
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('Rename'),
            onTap: () async {
              Navigator.pop(sheet);
              if (person.locked && !await ensureUnlocked(context)) return;
              if (context.mounted) _rename(context, c);
            },
          ),
          ListTile(
            leading: Icon(person.hidden ? Icons.visibility : Icons.visibility_off),
            title: Text(person.hidden ? 'Unhide' : 'Hide from People'),
            onTap: () async {
              Navigator.pop(sheet);
              if (!await ensureUnlocked(context)) return;
              await c.setHidden(person.id, !person.hidden);
            },
          ),
          ListTile(
            leading: Icon(person.locked ? Icons.lock_open : Icons.lock),
            title: Text(person.locked ? 'Remove passcode lock' : 'Protect with passcode'),
            onTap: () async {
              Navigator.pop(sheet);
              if (!await ensureUnlocked(context)) return;
              await c.setLocked(person.id, !person.locked);
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _rename(BuildContext context, FaceController c) async {
    final ctrl = TextEditingController(text: person.name ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Name this person'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Save')),
        ],
      ),
    );
    ctrl.dispose();
    if (name != null) await c.rename(person.id, name);
  }
}

class _HiddenScreen extends StatelessWidget {
  const _HiddenScreen();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<FaceController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Hidden people')),
      body: c.hidden.isEmpty
          ? const Center(child: Text('Nobody is hidden. Long-press a person to hide them.'))
          : _PeopleGrid(people: c.hidden, showUnlockedAlways: true),
    );
  }
}

class PersonDetailScreen extends StatelessWidget {
  const PersonDetailScreen({super.key, required this.person});
  final PersonCluster person;

  @override
  Widget build(BuildContext context) {
    final c = context.read<FaceController>();
    return Scaffold(
      appBar: AppBar(title: Text(person.displayName)),
      body: FutureBuilder<List<Object>>(
        future: Future.wait<Object>([c.assetIds(person.id), c.folders(person.id)]),
        builder: (_, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final ids = snap.data![0] as List<String>;
          final folders = snap.data![1] as Map<String, int>;
          return CustomScrollView(slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Appears in ${folders.length} folder(s)',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final e in folders.entries)
                      Chip(label: Text('${e.key} (${e.value})'), visualDensity: VisualDensity.compact),
                  ]),
                ]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(4),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3, mainAxisSpacing: 2, crossAxisSpacing: 2),
                itemCount: ids.length,
                itemBuilder: (_, i) => _GalleryThumb(assetId: ids[i]),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

class _GalleryThumb extends StatelessWidget {
  const _GalleryThumb({required this.assetId});
  final String assetId;

  @override
  Widget build(BuildContext context) => FutureBuilder<AssetEntity?>(
        future: AssetEntity.fromId(assetId),
        builder: (_, snap) {
          final a = snap.data;
          if (a == null) return const ColoredBox(color: Colors.black12);
          return AssetEntityImage(a,
              isOriginal: false,
              thumbnailSize: const ThumbnailSize.square(300),
              fit: BoxFit.cover);
        },
      );
}
