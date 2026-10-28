import 'package:sqflite/sqflite.dart';

import 'ocr_models.dart';

class OcrRepository {
  OcrRepository(this._db);
  final Database _db;

  Future<Map<String, int>> indexedModified() async {
    final rows = await _db.query('documents', columns: ['asset_id', 'modified']);
    return {for (final r in rows) r['asset_id'] as String: r['modified'] as int};
  }

  Future<void> upsert(DocumentRecord d) async {
    await _db.transaction((txn) async {
      final old = await txn.query('documents',
          columns: ['id'], where: 'asset_id = ?', whereArgs: [d.assetId]);
      if (old.isNotEmpty) {
        final id = old.first['id'] as int;
        await txn.delete('doc_fts', where: 'rowid = ?', whereArgs: [id]);
        await txn.delete('documents', where: 'id = ?', whereArgs: [id]);
      }
      final id = await txn.insert('documents', d.toMap());
      if (d.body.isNotEmpty) {
        await txn.insert('doc_fts', {'rowid': id, 'body': d.body});
      }
    });
  }

  static String _ftsQuery(String q) {
    final tokens = q
        .toLowerCase()
        .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
        .where((t) => t.isNotEmpty);
    return tokens.map((t) => '$t*').join(' ');
  }

  /// Offline keyword search (FTS4 prefix match) with optional type filter.
  Future<List<DocumentRecord>> search({
    String query = '',
    DocType? type,
    int limit = 300,
  }) async {
    final where = <String>["d.body != ''"];
    final args = <Object?>[];
    var join = '';
    final fts = _ftsQuery(query);
    if (fts.isNotEmpty) {
      join = 'JOIN doc_fts ON doc_fts.rowid = d.id';
      where.add('doc_fts MATCH ?');
      args.add(fts);
    }
    if (type != null) {
      where.add('d.doc_type = ?');
      args.add(type.name);
    }
    args.add(limit);
    final rows = await _db.rawQuery(
      'SELECT d.* FROM documents d $join WHERE ${where.join(' AND ')} '
      'ORDER BY d.doc_date DESC, d.id DESC LIMIT ?',
      args,
    );
    return rows.map(DocumentRecord.fromMap).toList();
  }

  Future<List<DocumentRecord>> taxDocuments() async {
    final rows = await _db.query('documents',
        where: "doc_type IN ('receipt','bill') AND body != ''");
    return rows.map(DocumentRecord.fromMap).toList();
  }

  Future<Map<DocType, int>> counts() async {
    final rows = await _db.rawQuery(
        "SELECT doc_type, COUNT(*) c FROM documents WHERE body != '' GROUP BY doc_type");
    return {
      for (final r in rows)
        DocType.values.firstWhere((t) => t.name == r['doc_type'],
            orElse: () => DocType.other): r['c'] as int
    };
  }
}
