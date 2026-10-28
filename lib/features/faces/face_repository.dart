import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../../core/utils/vector_math.dart';
import 'face_clusterer.dart';
import 'face_models.dart';

class FaceRepository {
  FaceRepository(this._db);
  final Database _db;

  Future<Set<String>> scannedAssetIds() async {
    final rows = await _db.query('face_scanned');
    return rows.map((r) => r['asset_id'] as String).toSet();
  }

  Future<void> saveFaces(String assetId, List<FaceRow> faces) async {
    final b = _db.batch();
    for (final f in faces) {
      b.insert('faces', {
        'asset_id': f.assetId,
        'album': f.album,
        'area': f.area,
        'embedding': f.embedding,
        'thumb': f.thumb,
      });
    }
    b.insert('face_scanned', {'asset_id': assetId},
        conflictAlgorithm: ConflictAlgorithm.ignore);
    await b.commit(noResult: true);
  }

  Future<List<FaceVec>> allVectors() async {
    final rows = await _db.query('faces', columns: ['id', 'embedding', 'cluster_id'], orderBy: 'id');
    return rows
        .map((r) => FaceVec(
              r['id'] as int,
              VectorMath.fromBytes(r['embedding'] as Uint8List),
              r['cluster_id'] as int?,
            ))
        .toList();
  }

  Future<void> applyClustering(ClusterOutput out) async {
    await _db.transaction((txn) async {
      // 1) Create real rows for brand-new clusters.
      final tempToReal = <int, int>{};
      for (final c in out.assignment.values.toSet()) {
        if (c < 0) tempToReal[c] = await txn.insert('face_clusters', {'hidden': 0, 'locked': 0});
      }
      // 2) Fold merged clusters' metadata (name / hidden / locked) into the survivor.
      for (final e in out.merged.entries) {
        final rows = await txn.query('face_clusters', where: 'id IN (?, ?)', whereArgs: [e.key, e.value]);
        final drop = rows.where((r) => r['id'] == e.key).firstOrNull;
        final keep = rows.where((r) => r['id'] == e.value).firstOrNull;
        if (drop != null && keep != null) {
          final keepName = keep['name'] as String?;
          await txn.update(
            'face_clusters',
            {
              'name': (keepName == null || keepName.isEmpty) ? drop['name'] : keepName,
              'hidden': ((keep['hidden'] as int) | (drop['hidden'] as int)),
              'locked': ((keep['locked'] as int) | (drop['locked'] as int)),
            },
            where: 'id = ?',
            whereArgs: [e.value],
          );
        }
        await txn.delete('face_clusters', where: 'id = ?', whereArgs: [e.key]);
      }
      // 3) Re-point faces.
      final b = txn.batch();
      out.assignment.forEach((faceId, c) {
        b.update('faces', {'cluster_id': c < 0 ? tempToReal[c] : c},
            where: 'id = ?', whereArgs: [faceId]);
      });
      await b.commit(noResult: true);
      await txn.rawDelete('DELETE FROM face_clusters WHERE id NOT IN '
          '(SELECT DISTINCT cluster_id FROM faces WHERE cluster_id IS NOT NULL)');
    });
  }

  Future<List<PersonCluster>> clusters() async {
    final rows = await _db.rawQuery('''
      SELECT c.id, c.name, c.hidden, c.locked,
             COUNT(f.id) AS face_count,
             COUNT(DISTINCT f.asset_id) AS photo_count,
             (SELECT thumb FROM faces WHERE cluster_id = c.id ORDER BY area DESC LIMIT 1) AS thumb
      FROM face_clusters c LEFT JOIN faces f ON f.cluster_id = c.id
      GROUP BY c.id HAVING face_count > 0
      ORDER BY photo_count DESC''');
    return rows
        .map((r) => PersonCluster(
              id: r['id'] as int,
              name: r['name'] as String?,
              hidden: (r['hidden'] as int) == 1,
              locked: (r['locked'] as int) == 1,
              faceCount: r['face_count'] as int,
              photoCount: r['photo_count'] as int,
              thumb: r['thumb'] as Uint8List?,
            ))
        .toList();
  }

  Future<void> update(int id, Map<String, Object?> values) =>
      _db.update('face_clusters', values, where: 'id = ?', whereArgs: [id]);

  Future<List<String>> assetIdsOf(int clusterId) async {
    final rows = await _db.rawQuery(
        'SELECT DISTINCT asset_id FROM faces WHERE cluster_id = ?', [clusterId]);
    return rows.map((r) => r['asset_id'] as String).toList();
  }

  /// Folders a person shows up in, with photo counts - "recurring individuals across folders".
  Future<Map<String, int>> foldersOf(int clusterId) async {
    final rows = await _db.rawQuery(
        'SELECT album, COUNT(DISTINCT asset_id) c FROM faces WHERE cluster_id = ? '
        'GROUP BY album ORDER BY c DESC',
        [clusterId]);
    return {for (final r in rows) r['album'] as String: r['c'] as int};
  }
}
