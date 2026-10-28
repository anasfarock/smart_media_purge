import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import 'ocr_models.dart';

class TaxExportResult {
  const TaxExportResult(this.root, this.fileCount);
  final String root;
  final int fileCount;
}

/// Copies receipts and bills into
///   <app documents>/tax_ready/<year>/<Receipts|Bills>/
/// and writes one summary.csv per year. Files never leave app-private storage.
class TaxOrganizer {
  Future<TaxExportResult> export(List<DocumentRecord> docs) async {
    final base = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(base.path, 'tax_ready'));
    final csv = <int, List<List<String>>>{};
    var count = 0;
    final df = DateFormat('yyyy-MM-dd');

    for (final d in docs) {
      if (d.type != DocType.receipt && d.type != DocType.bill) continue;
      final asset = await AssetEntity.fromId(d.assetId);
      final file = await asset?.originFile;
      if (asset == null || file == null) continue;

      final date = d.date ?? asset.createDateTime;
      final folder = Directory(p.join(
        root.path,
        '${date.year}',
        d.type == DocType.receipt ? 'Receipts' : 'Bills',
      ));
      await folder.create(recursive: true);

      final name = '${df.format(date)}_${_slug(d.merchant ?? 'unknown')}'
          '_${d.amount?.toStringAsFixed(2) ?? 'na'}_${d.id}${p.extension(file.path)}';
      final dest = p.join(folder.path, name);
      if (!await File(dest).exists()) await file.copy(dest);
      count++;

      csv.putIfAbsent(date.year, () => [
            ['date', 'category', 'merchant', 'amount', 'file']
          ]).add([
        df.format(date),
        d.type.label,
        d.merchant ?? '',
        d.amount?.toStringAsFixed(2) ?? '',
        name,
      ]);
    }

    for (final e in csv.entries) {
      final out = File(p.join(root.path, '${e.key}', 'summary.csv'));
      await out.writeAsString(e.value.map((r) => r.map(_esc).join(',')).join('\n'));
    }
    return TaxExportResult(root.path, count);
  }

  static String _slug(String s) {
    final t = s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    final trimmed = t.replaceAll(RegExp(r'^-+|-+$'), '');
    return trimmed.isEmpty ? 'unknown' : trimmed.substring(0, trimmed.length.clamp(0, 24));
  }

  static String _esc(String v) =>
      v.contains(RegExp(r'[",\n]')) ? '"${v.replaceAll('"', '""')}"' : v;
}
