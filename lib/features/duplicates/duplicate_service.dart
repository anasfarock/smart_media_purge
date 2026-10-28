import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/app_services.dart';
import '../../core/utils/perceptual_hash.dart';
import '../../core/utils/vector_math.dart';
import 'duplicate_models.dart';

typedef ProgressCallback = void Function(double progress, String message);

class DuplicateService {
  DuplicateService(this._s);
  final AppServices _s;

  static const _thumb = ThumbnailSize(256, 256);

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  /// [sensitivity] 0 = only near-certain matches, 1 = very permissive.
  Future<List<DuplicateGroup>> scan({
    double sensitivity = 0.5,
    ProgressCallback? onProgress,
  }) async {
    final embeddingThreshold = _lerp(0.97, 0.85, sensitivity);
    final strictHamming = _lerp(4, 14, sensitivity).round();
    final candidateHamming =
        (_s.imageEmbedder.isReady ? _lerp(18, 30, sensitivity) : strictHamming).round();

    final assets = await _s.media.loadImages();
    final cached = await _loadCache();
    final fps = <String, MediaFingerprint>{};
    final byId = <String, AssetEntity>{};

    // ---- Phase 1: fingerprint every image (cached by modified time) ----------
    for (var i = 0; i < assets.length; i++) {
      final a = assets[i];
      onProgress?.call(0.6 * i / math.max(assets.length, 1),
          'Analysing ${i + 1} of ${assets.length}');
      final old = cached[a.id];
      final fp = await _fingerprint(a, old);
      if (fp != null) {
        fps[a.id] = fp;
        byId[a.id] = a;
        if (!identical(fp, old)) await _save(fp);
      }
      if (i % 8 == 0) await Future<void>.delayed(Duration.zero);
    }

    // ---- Phase 2: exact duplicates (SHA-256, only for equal-size files) -------
    onProgress?.call(0.62, 'Looking for exact copies');
    final bySize = <int, List<String>>{};
    fps.forEach((id, fp) => bySize.putIfAbsent(fp.sizeBytes, () => []).add(id));
    final bySha = <String, List<String>>{};
    for (final ids in bySize.values) {
      if (ids.length < 2) continue;
      for (final id in ids) {
        final fp = fps[id]!;
        if (fp.sha256 == null) {
          fp.sha256 = await _hashFile(byId[id]!);
          await _save(fp);
        }
        if (fp.sha256 != null) bySha.putIfAbsent(fp.sha256!, () => []).add(id);
      }
    }
    bySha.removeWhere((_, v) => v.length < 2);

    final repMembers = <String, List<String>>{};
    final inExact = <String>{};
    for (final ids in bySha.values) {
      repMembers[ids.first] = ids;
      inExact.addAll(ids);
    }
    final reps = <String>[];
    for (final id in fps.keys) {
      if (!inExact.contains(id)) {
        reps.add(id);
        repMembers[id] = [id];
      } else if (repMembers.containsKey(id)) {
        reps.add(id);
      }
    }

    // ---- Phase 3: visually similar (dHash pre-filter + embedding check) -------
    final uf = _UnionFind(reps.length);
    for (var i = 0; i < reps.length; i++) {
      final a = fps[reps[i]]!;
      for (var j = i + 1; j < reps.length; j++) {
        final b = fps[reps[j]]!;
        final ham = PerceptualHash.hamming(a.dhash, b.dhash);
        if (ham > candidateHamming) continue;
        final bool similar;
        if (a.embedding != null && b.embedding != null) {
          similar = VectorMath.dot(a.embedding!, b.embedding!) >= embeddingThreshold;
        } else {
          similar = ham <= strictHamming;
        }
        if (similar) uf.union(i, j);
      }
      if (i % 200 == 0) {
        onProgress?.call(0.65 + 0.3 * i / math.max(reps.length, 1),
            'Comparing photos');
        await Future<void>.delayed(Duration.zero);
      }
    }

    // ---- Phase 4: build groups and recommend the keeper -----------------------
    final comps = <int, List<int>>{};
    for (var i = 0; i < reps.length; i++) {
      comps.putIfAbsent(uf.find(i), () => []).add(i);
    }
    final groups = <DuplicateGroup>[];
    var gid = 0;
    for (final comp in comps.values) {
      final ids = comp.expand((i) => repMembers[reps[i]]!).toList();
      if (ids.length < 2) continue;
      final items = ids
          .map((id) => DuplicateItem(asset: byId[id]!, fp: fps[id]!))
          .toList()
        ..sort(DuplicateItem.rank);
      groups.add(DuplicateGroup(id: gid++, items: items, exact: comp.length == 1));
    }
    int reclaim(DuplicateGroup g) =>
        g.items.skip(1).fold<int>(0, (s, e) => s + e.fp.sizeBytes);
    groups.sort((a, b) => reclaim(b).compareTo(reclaim(a)));

    onProgress?.call(1, 'Done');
    return groups;
  }

  Future<List<String>> delete(List<String> ids) async {
    if (ids.isEmpty) return [];
    final deleted = await PhotoManager.editor.deleteWithIds(ids);
    for (final id in deleted) {
      await _s.db.db.delete('fingerprints', where: 'asset_id = ?', whereArgs: [id]);
    }
    return deleted;
  }

  // ---------------------------------------------------------------------------

  Future<MediaFingerprint?> _fingerprint(AssetEntity a, MediaFingerprint? cached) async {
    final modified = a.modifiedDateSecond ?? 0;
    if (cached != null &&
        cached.modified == modified &&
        (cached.embedding != null) == _s.imageEmbedder.isReady) {
      return cached;
    }
    final file = await a.originFile;
    if (file == null) return null;
    final size = await file.length();
    final bytes = await a.thumbnailDataWithSize(_thumb);
    if (bytes == null) return null;
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    return MediaFingerprint(
      assetId: a.id,
      modified: modified,
      sizeBytes: size,
      width: a.width,
      height: a.height,
      ext: p.extension(file.path).toLowerCase(),
      dhash: PerceptualHash.dHash(decoded),
      embedding: _s.imageEmbedder.embed(decoded),
    );
  }

  Future<String?> _hashFile(AssetEntity a) async {
    final File? f = await a.originFile;
    if (f == null) return null;
    final digest = await sha256.bind(f.openRead()).first;
    return digest.toString();
  }

  Future<Map<String, MediaFingerprint>> _loadCache() async {
    final rows = await _s.db.db.query('fingerprints');
    return {for (final r in rows) r['asset_id'] as String: MediaFingerprint.fromMap(r)};
  }

  Future<void> _save(MediaFingerprint fp) => _s.db.db.insert(
        'fingerprints',
        fp.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
}

class _UnionFind {
  _UnionFind(int n) : _parent = List<int>.generate(n, (i) => i);
  final List<int> _parent;

  int find(int x) {
    while (_parent[x] != x) {
      _parent[x] = _parent[_parent[x]];
      x = _parent[x];
    }
    return x;
  }

  void union(int a, int b) {
    final ra = find(a), rb = find(b);
    if (ra != rb) _parent[rb] = ra;
  }
}
