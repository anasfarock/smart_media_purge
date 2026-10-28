import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Single local SQLite database shared by all modules. Nothing leaves the device.
class AppDatabase {
  AppDatabase._(this.db);
  final Database db;

  static Future<AppDatabase> open() async {
    final path = p.join(await getDatabasesPath(), 'smart_media_purge.db');
    final db = await openDatabase(path, version: 1, onCreate: _create);
    return AppDatabase._(db);
  }

  static Future<void> _create(Database db, int version) async {
    final b = db.batch();

    // Module 1 - duplicates
    b.execute('''
      CREATE TABLE fingerprints (
        asset_id   TEXT PRIMARY KEY,
        modified   INTEGER NOT NULL,
        size_bytes INTEGER NOT NULL,
        width      INTEGER NOT NULL,
        height     INTEGER NOT NULL,
        ext        TEXT NOT NULL,
        sha256     TEXT,
        dhash      INTEGER NOT NULL,
        embedding  BLOB
      )''');
    b.execute('CREATE INDEX idx_fp_size ON fingerprints(size_bytes)');

    // Module 2 - OCR documents (+ FTS4 index for offline keyword search)
    b.execute('''
      CREATE TABLE documents (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        asset_id        TEXT NOT NULL UNIQUE,
        modified        INTEGER NOT NULL,
        doc_type        TEXT NOT NULL,
        body            TEXT NOT NULL,
        merchant        TEXT,
        amount          REAL,
        doc_date        INTEGER,
        sensitive_count INTEGER NOT NULL DEFAULT 0
      )''');
    b.execute('CREATE INDEX idx_doc_type ON documents(doc_type)');
    b.execute(
        'CREATE VIRTUAL TABLE doc_fts USING fts4(body, tokenize=unicode61)');

    // Module 3 - faces
    b.execute('''
      CREATE TABLE face_clusters (
        id     INTEGER PRIMARY KEY AUTOINCREMENT,
        name   TEXT,
        hidden INTEGER NOT NULL DEFAULT 0,
        locked INTEGER NOT NULL DEFAULT 0
      )''');
    b.execute('''
      CREATE TABLE faces (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        asset_id   TEXT NOT NULL,
        album      TEXT NOT NULL,
        area       REAL NOT NULL,
        embedding  BLOB NOT NULL,
        thumb      BLOB NOT NULL,
        cluster_id INTEGER
      )''');
    b.execute('CREATE INDEX idx_faces_cluster ON faces(cluster_id)');
    b.execute('CREATE INDEX idx_faces_asset ON faces(asset_id)');
    b.execute('CREATE TABLE face_scanned (asset_id TEXT PRIMARY KEY)');

    await b.commit(noResult: true);
  }
}
